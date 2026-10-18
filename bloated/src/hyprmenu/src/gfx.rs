//! EGL + OpenGL ES 2 rendering with GLSL shaders: a glyph atlas, batched textured
//! quads, and a fragment-shader spinner. Colors are written premultiplied, which is
//! what the compositor expects from an ARGB surface.

use crate::text::Fonts;
use glow::HasContext;
use khronos_egl as egl;
use std::collections::HashMap;
use wayland_client::Proxy;

const ATLAS: i32 = 1024;

const VS: &str = r#"#version 100
attribute vec2 a_pos; attribute vec2 a_uv; attribute vec4 a_col;
uniform vec2 u_res;
varying vec2 v_uv; varying vec4 v_col;
void main() {
  v_uv = a_uv; v_col = a_col;
  vec2 p = a_pos / u_res * 2.0 - 1.0;
  gl_Position = vec4(p.x, -p.y, 0.0, 1.0);
}"#;

// glyphs and solid rects: atlas coverage × color
const FS_TEX: &str = r#"#version 100
precision mediump float;
uniform sampler2D u_tex;
varying vec2 v_uv; varying vec4 v_col;
void main() {
  float a = texture2D(u_tex, v_uv).a * v_col.a;
  gl_FragColor = vec4(v_col.rgb * a, a);
}"#;

// spinner: signed-distance ring of 8 dots fading by phase; v_uv is a [-1,1] local frame,
// u_px is one pixel in those units for anti-aliasing
const FS_SPIN: &str = r#"#version 100
precision mediump float;
uniform float u_tick; uniform float u_px;
varying vec2 v_uv; varying vec4 v_col;
void main() {
  float best = 0.0;
  for (int i = 0; i < 8; i++) {
    float ang = 6.2831853 * float(i) / 8.0;
    vec2 c = 0.62 * vec2(cos(ang), sin(ang));
    float d = length(v_uv - c) - 0.17;
    float cov = clamp(0.5 - d / u_px, 0.0, 1.0);
    float ph = mod(float(i) - u_tick, 8.0) / 7.0;
    best = max(best, cov * (0.15 + 0.85 * ph));
  }
  float a = best * v_col.a;
  gl_FragColor = vec4(v_col.rgb * a, a);
}"#;

#[derive(Clone, Copy)]
struct GlyphUv { w: i32, h: i32, left: i32, top: i32, adv: f32, u0: f32, v0: f32, u1: f32, v1: f32 }

pub struct Rgb(pub u32);
impl Rgb { fn f(&self) -> [f32; 3] { [((self.0 >> 16) & 255) as f32 / 255.0, ((self.0 >> 8) & 255) as f32 / 255.0, (self.0 & 255) as f32 / 255.0] } }

/// The long-lived GL state: EGL display/context, programs, atlas. Survives window hide/show.
pub struct Gfx {
    egl: egl::DynamicInstance<egl::EGL1_4>,
    display: egl::Display,
    config: egl::Config,
    context: egl::Context,
    gl: glow::Context,
    prog_tex: glow::Program, prog_spin: glow::Program,
    u_tex_res: Option<glow::UniformLocation>, u_tex_tex: Option<glow::UniformLocation>,
    u_spin_res: Option<glow::UniformLocation>, u_spin_tick: Option<glow::UniformLocation>, u_spin_px: Option<glow::UniformLocation>,
    vbo: glow::Buffer,
    atlas: glow::Texture,
    glyphs: HashMap<(char, bool), GlyphUv>,
    atlas_x: i32, atlas_y: i32, atlas_row_h: i32,
    verts: Vec<f32>, // x y u v r g b a
    pw: i32, ph: i32,
}

/// Per-window GL surface.
pub struct Surface {
    wl_egl: wayland_egl::WlEglSurface,
    egl_surface: egl::Surface,
    pub w: i32, pub h: i32,
}

fn compile(gl: &glow::Context, kind: u32, src: &str) -> Result<glow::Shader, String> {
    unsafe {
        let sh = gl.create_shader(kind)?;
        gl.shader_source(sh, src);
        gl.compile_shader(sh);
        if !gl.get_shader_compile_status(sh) { return Err(format!("shader: {}", gl.get_shader_info_log(sh))); }
        Ok(sh)
    }
}
fn program(gl: &glow::Context, fs: &str) -> Result<glow::Program, String> {
    unsafe {
        let p = gl.create_program()?;
        gl.attach_shader(p, compile(gl, glow::VERTEX_SHADER, VS)?);
        gl.attach_shader(p, compile(gl, glow::FRAGMENT_SHADER, fs)?);
        gl.bind_attrib_location(p, 0, "a_pos"); gl.bind_attrib_location(p, 1, "a_uv"); gl.bind_attrib_location(p, 2, "a_col");
        gl.link_program(p);
        if !gl.get_program_link_status(p) { return Err(format!("link: {}", gl.get_program_info_log(p))); }
        Ok(p)
    }
}

impl Gfx {
    /// `display_ptr` is the libwayland `wl_display*`.
    pub fn new(display_ptr: *mut std::ffi::c_void) -> Result<Gfx, String> {
        let lib = unsafe { libloading::Library::new("libEGL.so.1") }.map_err(|e| format!("libEGL: {e}"))?;
        let egl = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required_from(lib) }.map_err(|e| format!("EGL load: {e}"))?;
        let display = unsafe { egl.get_display(display_ptr) }.ok_or("eglGetDisplay failed")?;
        egl.initialize(display).map_err(|e| format!("eglInitialize: {e}"))?;
        egl.bind_api(egl::OPENGL_ES_API).map_err(|e| format!("bind_api: {e}"))?;
        let attrs = [egl::SURFACE_TYPE, egl::WINDOW_BIT, egl::RED_SIZE, 8, egl::GREEN_SIZE, 8, egl::BLUE_SIZE, 8, egl::ALPHA_SIZE, 8,
                     egl::RENDERABLE_TYPE, egl::OPENGL_ES2_BIT, egl::NONE];
        let config = egl.choose_first_config(display, &attrs).map_err(|e| format!("choose_config: {e}"))?.ok_or("no EGL config with alpha")?;
        let context = egl.create_context(display, config, None, &[egl::CONTEXT_CLIENT_VERSION, 2, egl::NONE]).map_err(|e| format!("create_context: {e}"))?;
        // surfaceless current context (EGL_KHR_surfaceless_context, standard in Mesa) so GL
        // objects can be created before any window exists
        egl.make_current(display, None, None, Some(context)).map_err(|e| format!("surfaceless make_current: {e}"))?;

        let gl = unsafe { glow::Context::from_loader_function(|s| egl.get_proc_address(s).map_or(std::ptr::null(), |p| p as *const _)) };
        let (prog_tex, prog_spin) = (program(&gl, FS_TEX)?, program(&gl, FS_SPIN)?);
        let (vbo, atlas) = unsafe { (gl.create_buffer()?, gl.create_texture()?) };
        let mut g = Gfx {
            u_tex_res: unsafe { gl.get_uniform_location(prog_tex, "u_res") }, u_tex_tex: unsafe { gl.get_uniform_location(prog_tex, "u_tex") },
            u_spin_res: unsafe { gl.get_uniform_location(prog_spin, "u_res") }, u_spin_tick: unsafe { gl.get_uniform_location(prog_spin, "u_tick") },
            u_spin_px: unsafe { gl.get_uniform_location(prog_spin, "u_px") },
            egl, display, config, context, gl, prog_tex, prog_spin, vbo, atlas,
            glyphs: HashMap::new(), atlas_x: 0, atlas_y: 0, atlas_row_h: 0, verts: Vec::new(), pw: 0, ph: 0,
        };
        unsafe {
            let gl = &g.gl;
            gl.bind_texture(glow::TEXTURE_2D, Some(atlas));
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, glow::NEAREST as i32);
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER, glow::NEAREST as i32);
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE as i32);
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE as i32);
            gl.pixel_store_i32(glow::UNPACK_ALIGNMENT, 1);
        }
        g.atlas_reset();
        Ok(g)
    }

    /// Forget all glyphs (font size changed) and clear the texture.
    pub fn atlas_reset(&mut self) {
        self.glyphs.clear();
        let zero = vec![0u8; (ATLAS * ATLAS) as usize];
        unsafe {
            self.gl.bind_texture(glow::TEXTURE_2D, Some(self.atlas));
            self.gl.tex_image_2d(glow::TEXTURE_2D, 0, glow::ALPHA as i32, ATLAS, ATLAS, 0, glow::ALPHA, glow::UNSIGNED_BYTE, glow::PixelUnpackData::Slice(Some(&zero)));
            // 4x4 solid block at the origin for rectangles
            self.gl.tex_sub_image_2d(glow::TEXTURE_2D, 0, 0, 0, 4, 4, glow::ALPHA, glow::UNSIGNED_BYTE, glow::PixelUnpackData::Slice(Some(&[255u8; 16])));
        }
        self.atlas_x = 6; self.atlas_y = 0; self.atlas_row_h = 4;
    }

    pub fn create_surface(&mut self, wl_surface: &wayland_client::protocol::wl_surface::WlSurface, w: i32, h: i32) -> Result<Surface, String> {
        let wl_egl = wayland_egl::WlEglSurface::new(wl_surface.id(), w, h).map_err(|e| format!("wl_egl_window: {e:?}"))?;
        let egl_surface = unsafe { self.egl.create_window_surface(self.display, self.config, wl_egl.ptr() as egl::NativeWindowType, None) }
            .map_err(|e| format!("eglCreateWindowSurface: {e}"))?;
        self.egl.make_current(self.display, Some(egl_surface), Some(egl_surface), Some(self.context)).map_err(|e| format!("make_current: {e}"))?;
        let _ = self.egl.swap_interval(self.display, 0); // paced by frame callbacks, not vsync blocking
        Ok(Surface { wl_egl, egl_surface, w, h })
    }
    pub fn destroy_surface(&mut self, s: Surface) {
        let _ = self.egl.make_current(self.display, None, None, None);
        let _ = self.egl.destroy_surface(self.display, s.egl_surface);
        drop(s.wl_egl);
    }
    pub fn resize(&mut self, s: &mut Surface, w: i32, h: i32) {
        if (w, h) != (s.w, s.h) { s.wl_egl.resize(w, h, 0, 0); s.w = w; s.h = h; }
    }

    fn glyph(&mut self, fonts: &Fonts, ch: char, bold: bool) -> GlyphUv {
        if let Some(g) = self.glyphs.get(&(ch, bold)) { return *g; }
        let r = fonts.raster(ch, bold);
        let mut g = GlyphUv { w: 0, h: 0, left: 0, top: 0, adv: fonts.cell_w as f32, u0: 0.0, v0: 0.0, u1: 0.0, v1: 0.0 };
        if let Some(r) = r {
            g.adv = r.adv; g.left = r.left; g.top = r.top;
            if r.w > 0 && r.h > 0 {
                if self.atlas_x + r.w + 1 > ATLAS { self.atlas_x = 0; self.atlas_y += self.atlas_row_h + 1; self.atlas_row_h = 0; }
                if self.atlas_y + r.h + 1 <= ATLAS {
                    unsafe {
                        self.gl.bind_texture(glow::TEXTURE_2D, Some(self.atlas));
                        self.gl.tex_sub_image_2d(glow::TEXTURE_2D, 0, self.atlas_x, self.atlas_y, r.w, r.h, glow::ALPHA, glow::UNSIGNED_BYTE, glow::PixelUnpackData::Slice(Some(&r.data)));
                    }
                    g.w = r.w; g.h = r.h;
                    g.u0 = self.atlas_x as f32 / ATLAS as f32; g.v0 = self.atlas_y as f32 / ATLAS as f32;
                    g.u1 = (self.atlas_x + r.w) as f32 / ATLAS as f32; g.v1 = (self.atlas_y + r.h) as f32 / ATLAS as f32;
                    self.atlas_x += r.w + 1; self.atlas_row_h = self.atlas_row_h.max(r.h);
                }
            }
        }
        self.glyphs.insert((ch, bold), g);
        g
    }

    // ---- frame ----

    pub fn begin(&mut self, s: &Surface, bg: Rgb, bg_alpha: f32) {
        self.pw = s.w; self.ph = s.h;
        let c = bg.f();
        unsafe {
            self.gl.viewport(0, 0, s.w, s.h);
            self.gl.clear_color(c[0] * bg_alpha, c[1] * bg_alpha, c[2] * bg_alpha, bg_alpha);
            self.gl.clear(glow::COLOR_BUFFER_BIT);
            self.gl.enable(glow::BLEND);
            self.gl.blend_func(glow::ONE, glow::ONE_MINUS_SRC_ALPHA);
            self.gl.active_texture(glow::TEXTURE0);
            self.gl.bind_texture(glow::TEXTURE_2D, Some(self.atlas));
        }
        self.verts.clear();
    }

    fn quad(&mut self, x0: f32, y0: f32, x1: f32, y1: f32, u0: f32, v0: f32, u1: f32, v1: f32, c: &Rgb, a: f32) {
        let [r, g, b] = c.f();
        let v = |x: f32, y: f32, u: f32, w: f32| [x, y, u, w, r, g, b, a];
        for p in [v(x0, y0, u0, v0), v(x1, y0, u1, v0), v(x1, y1, u1, v1), v(x0, y0, u0, v0), v(x1, y1, u1, v1), v(x0, y1, u0, v1)] { self.verts.extend_from_slice(&p); }
    }
    pub fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, c: &Rgb, a: f32) {
        let u = 2.0 / ATLAS as f32; self.quad(x, y, x + w, y + h, u, u, u, u, c, a);
    }
    /// Draw a string at pen (x, baseline y). `bold_idx` are char indices to emphasize. Returns advance.
    pub fn text(&mut self, fonts: &Fonts, x: f32, y: f32, s: &str, c: &Rgb, a: f32, bold_idx: &[usize]) -> f32 {
        let mut pen = x;
        for (i, ch) in s.chars().enumerate() {
            let g = self.glyph(fonts, ch, bold_idx.contains(&i));
            if g.w > 0 && g.h > 0 {
                let (ox, oy) = (pen.round() + g.left as f32, y.round() - g.top as f32);
                self.quad(ox, oy, ox + g.w as f32, oy + g.h as f32, g.u0, g.v0, g.u1, g.v1, c, a);
            }
            pen += g.adv;
        }
        pen - x
    }

    fn flush(&mut self, prog: glow::Program) {
        if self.verts.is_empty() { return; }
        unsafe {
            let gl = &self.gl;
            gl.use_program(Some(prog));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(self.vbo));
            let bytes = std::slice::from_raw_parts(self.verts.as_ptr() as *const u8, self.verts.len() * 4);
            gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STREAM_DRAW);
            let stride = 8 * 4;
            gl.enable_vertex_attrib_array(0); gl.vertex_attrib_pointer_f32(0, 2, glow::FLOAT, false, stride, 0);
            gl.enable_vertex_attrib_array(1); gl.vertex_attrib_pointer_f32(1, 2, glow::FLOAT, false, stride, 8);
            gl.enable_vertex_attrib_array(2); gl.vertex_attrib_pointer_f32(2, 4, glow::FLOAT, false, stride, 16);
            gl.draw_arrays(glow::TRIANGLES, 0, (self.verts.len() / 8) as i32);
        }
        self.verts.clear();
    }
    /// Submit everything queued so far with the glyph/rect shader.
    pub fn flush_text(&mut self) {
        unsafe {
            self.gl.use_program(Some(self.prog_tex));
            self.gl.uniform_2_f32(self.u_tex_res.as_ref(), self.pw as f32, self.ph as f32);
            self.gl.uniform_1_i32(self.u_tex_tex.as_ref(), 0);
        }
        self.flush(self.prog_tex);
    }
    pub fn spinner(&mut self, cx: f32, cy: f32, size: f32, tick: u32, c: &Rgb) {
        let h = size / 2.0;
        self.quad(cx - h, cy - h, cx + h, cy + h, -1.0, -1.0, 1.0, 1.0, c, 1.0);
        unsafe {
            self.gl.use_program(Some(self.prog_spin));
            self.gl.uniform_2_f32(self.u_spin_res.as_ref(), self.pw as f32, self.ph as f32);
            self.gl.uniform_1_f32(self.u_spin_tick.as_ref(), tick as f32);
            self.gl.uniform_1_f32(self.u_spin_px.as_ref(), 2.0 / size);
        }
        self.flush(self.prog_spin);
    }
    /// Attaches the buffer and commits the surface.
    pub fn end(&mut self, s: &Surface) -> Result<(), String> {
        self.egl.swap_buffers(self.display, s.egl_surface).map_err(|e| format!("swap: {e}"))
    }
}
