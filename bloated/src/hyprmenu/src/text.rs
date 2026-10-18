//! Font loading and glyph rasterization (freetype). Fontconfig lookup is done once via
//! `fc-match`, which keeps a native dependency out of the build.

use freetype as ft;

pub const FAMILY: &str = "Hack Nerd Font";
pub const SIZE_PT: f64 = 9.4; // alacritty font.size

pub struct Raster {
    pub w: i32, pub h: i32, pub left: i32, pub top: i32, pub adv: f32,
    pub data: Vec<u8>, // coverage, w*h, tightly packed
}

pub struct Fonts {
    _lib: ft::Library,
    faces: [ft::Face; 2], // regular, bold
    pub cell_w: f64,
    pub line_h: f64,
    pub ascent: f64,
}

fn font_file(style: &str) -> Result<String, String> {
    let out = std::process::Command::new("fc-match").arg("-f").arg("%{file}").arg(format!("{FAMILY}:style={style}")).output()
        .map_err(|e| format!("fc-match: {e}"))?;
    let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if path.is_empty() { return Err(format!("font not found: {FAMILY} {style}")); }
    Ok(path)
}

impl Fonts {
    pub fn load() -> Result<Fonts, String> {
        let lib = ft::Library::init().map_err(|e| format!("freetype: {e}"))?;
        let mut faces = Vec::new();
        for style in ["Regular", "Bold"] {
            let path = font_file(style)?;
            faces.push(lib.new_face(&path, 0).map_err(|e| format!("{path}: {e}"))?);
        }
        let mut f = Fonts { _lib: lib, faces: [faces.remove(0), faces.remove(0)], cell_w: 0.0, line_h: 0.0, ascent: 0.0 };
        f.set_scale(1.0)?;
        Ok(f)
    }

    /// Size the faces for a fractional scale; metrics come out in physical pixels.
    pub fn set_scale(&mut self, scale: f64) -> Result<(), String> {
        let size = (SIZE_PT * scale * 64.0 + 0.5) as isize;
        for face in &self.faces { face.set_char_size(0, size, 96, 96).map_err(|e| format!("set_char_size: {e}"))?; }
        let f = &self.faces[0];
        f.load_char('M' as usize, ft::face::LoadFlag::DEFAULT).map_err(|e| format!("{e}"))?;
        self.cell_w = f.glyph().advance().x as f64 / 64.0;
        let m = f.size_metrics().ok_or("no size metrics")?;
        self.line_h = m.height as f64 / 64.0;
        self.ascent = m.ascender as f64 / 64.0;
        Ok(())
    }

    pub fn raster(&self, ch: char, bold: bool) -> Option<Raster> {
        let mut face = &self.faces[bold as usize];
        let mut idx = face.get_char_index(ch as usize);
        if idx.is_none() && bold { face = &self.faces[0]; idx = face.get_char_index(ch as usize); }
        let idx = idx.unwrap_or(0);
        face.load_glyph(idx, ft::face::LoadFlag::RENDER | ft::face::LoadFlag::TARGET_LIGHT).ok()?;
        let g = face.glyph();
        let b = g.bitmap();
        let (w, h, pitch) = (b.width(), b.rows(), b.pitch());
        let src = b.buffer();
        let mut data = Vec::with_capacity((w * h) as usize);
        for y in 0..h as usize {
            let row = &src[y * pitch as usize..y * pitch as usize + w as usize];
            data.extend_from_slice(row);
        }
        Some(Raster { w, h, left: g.bitmap_left(), top: g.bitmap_top(), adv: g.advance().x as f32 / 64.0, data })
    }
}
