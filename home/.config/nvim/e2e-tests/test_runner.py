#!/usr/bin/env python3
"""
E2E test runner for Neovim config
Pure Python stdlib - uses pty to drive real nvim instance

Usage:
  python3 e2e-tests/test_runner.py                    # Run all tests
  python3 e2e-tests/test_runner.py TestMakeRunner     # Run specific test class
  python3 e2e-tests/test_runner.py TestMakeRunner.test_filter_targets  # Run specific test
  DEBUG_NVIM_SCREEN=1 python3 e2e-tests/test_runner.py  # Debug mode (show screen output)
"""

import os
import pty
import select
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


class NvimTerminal:
    """Drives nvim in a real terminal via pty"""

    def __init__(self, config_dir, width=120, height=30):
        self.config_dir = Path(config_dir)
        self.init_lua = self.config_dir / 'init.lua'
        self.width = width
        self.height = height
        self.master_fd = None
        self.pid = None
        self.output_buffer = b''
        # Terminal emulation: maintain a grid of current screen state
        self.grid = [[' ' for _ in range(width)] for _ in range(height)]
        self.cursor_row = 0
        self.cursor_col = 0

    def start(self, cwd=None, filename=None):
        """Start nvim in a pty"""
        import shutil
        # Find nvim in PATH (try multiple names)
        nvim_path = None
        for name in ['nvim', 'vi', 'vim']:
            nvim_path = shutil.which(name)
            if nvim_path:
                break
        if not nvim_path:
            raise RuntimeError("nvim/vi/vim not found in PATH")
        cmd = [nvim_path, '-u', str(self.init_lua)]
        if filename:
            cmd.append(str(filename))
        # Set terminal size
        env = os.environ.copy()
        env['LINES'] = str(self.height)
        env['COLUMNS'] = str(self.width)
        env['TERM'] = 'xterm-256color'
        # Spawn in pty
        self.pid, self.master_fd = pty.fork()
        if self.pid == 0:  # Child process
            if cwd:
                os.chdir(cwd)
            os.execve(nvim_path, cmd, env)
        else:  # Parent process
            # Give nvim time to start
            time.sleep(0.03)
            # Read initial output
            self._read_output(timeout=0.01)

    def send_keys(self, keys):
        """Send keystrokes to nvim (one by one)"""
        for char in keys:
            if char == '\n':
                # Enter key
                os.write(self.master_fd, b'\r')
            elif char == '\x1b':
                # Escape key
                os.write(self.master_fd, b'\x1b')
            else:
                os.write(self.master_fd, char.encode('utf-8'))
            time.sleep(0.002)  # Small delay between keys
        # Wait a bit for nvim to process
        time.sleep(0.01)
        self._read_output(timeout=0.02)

    def send_ctrl(self, char):
        """Send Ctrl+key combination, only works for A-Z"""
        # Ctrl+key is key code minus 64 (works for A-Z)
        code = ord(char.upper()) - 64
        os.write(self.master_fd, bytes([code]))
        time.sleep(0.005)
        self._read_output(timeout=0.01)

    def _read_output(self, timeout=0.5):
        """Read available output from nvim and update terminal grid"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            # Check if data is available
            ready, _, _ = select.select([self.master_fd], [], [], 0.01)
            if ready:
                try:
                    data = os.read(self.master_fd, 4096)
                    self.output_buffer += data
                    # Update grid with new data
                    self._process_output(data)
                except OSError:
                    break
            else:
                break

    def _process_output(self, data):
        """Process terminal output and update grid"""
        import re

        text = data.decode('utf-8', errors='ignore')
        i = 0
        while i < len(text):
            char = text[i]
            # Handle escape sequences
            if char == '\x1b':
                # Try to parse CSI sequence
                match = re.match(r'\x1b\[([0-9;?]*)([a-zA-Z])', text[i:])
                if match:
                    params_str = match.group(1)
                    cmd = match.group(2)
                    # Strip '?' prefix if present (used for private sequences)
                    if params_str.startswith('?'):
                        params_str = params_str[1:]
                    params = [int(p) if p else 0 for p in params_str.split(';') if p] if params_str else []
                    # Cursor position (H or f)
                    if cmd in ('H', 'f'):
                        row = params[0] - 1 if len(params) > 0 and params[0] > 0 else 0
                        col = params[1] - 1 if len(params) > 1 and params[1] > 0 else 0
                        self.cursor_row = max(0, min(row, self.height - 1))
                        self.cursor_col = max(0, min(col, self.width - 1))
                    # Cursor up (A)
                    elif cmd == 'A':
                        n = params[0] if params else 1
                        self.cursor_row = max(0, self.cursor_row - n)
                    # Cursor down (B)
                    elif cmd == 'B':
                        n = params[0] if params else 1
                        self.cursor_row = min(self.height - 1, self.cursor_row + n)
                    # Cursor forward (C)
                    elif cmd == 'C':
                        n = params[0] if params else 1
                        self.cursor_col = min(self.width - 1, self.cursor_col + n)
                    # Cursor back (D)
                    elif cmd == 'D':
                        n = params[0] if params else 1
                        self.cursor_col = max(0, self.cursor_col - n)
                    # Clear screen (J)
                    elif cmd == 'J':
                        mode = params[0] if params else 0
                        if mode == 2:  # Clear entire screen
                            self.grid = [[' ' for _ in range(self.width)] for _ in range(self.height)]
                            self.cursor_row = 0
                            self.cursor_col = 0
                    # Clear line (K)
                    elif cmd == 'K':
                        mode = params[0] if params else 0
                        if mode == 0:  # Clear from cursor to end of line
                            for c in range(self.cursor_col, self.width):
                                self.grid[self.cursor_row][c] = ' '
                        elif mode == 2:  # Clear entire line
                            self.grid[self.cursor_row] = [' ' for _ in range(self.width)]
                    i += len(match.group(0))
                    continue
                # Skip other escape sequences
                other_match = re.match(r'\x1b[\[\]><=\(][^\x1b]*?[\x07a-zA-Z\\]', text[i:])
                if other_match:
                    i += len(other_match.group(0))
                    continue
                i += 1
                continue
            # Handle regular characters
            if char == '\r':
                self.cursor_col = 0
            elif char == '\n':
                self.cursor_row = min(self.height - 1, self.cursor_row + 1)
                self.cursor_col = 0
            elif char == '\b':
                self.cursor_col = max(0, self.cursor_col - 1)
            elif char == '\t':
                # Tab to next 8-column boundary
                self.cursor_col = min(self.width - 1, ((self.cursor_col + 8) // 8) * 8)
            elif ord(char) >= 32:  # Printable character
                if self.cursor_row < self.height and self.cursor_col < self.width:
                    self.grid[self.cursor_row][self.cursor_col] = char
                    self.cursor_col += 1
                    if self.cursor_col >= self.width:
                        self.cursor_col = 0
                        self.cursor_row = min(self.height - 1, self.cursor_row + 1)
            i += 1

    def get_grid(self):
        """Get current terminal grid as text (current screen state only)"""
        # Read any pending output first
        self._read_output(timeout=0.005)
        # Convert grid to text
        lines = []
        for row in self.grid:
            line = ''.join(row).rstrip()  # Remove trailing spaces
            lines.append(line)
        # Remove trailing empty lines
        while lines and not lines[-1]:
            lines.pop()
        result = '\n'.join(lines)
        # Debug output if env var is set
        if os.environ.get('DEBUG_NVIM_SCREEN'):
            print(f"\n=== GRID OUTPUT ===\n{result}\n===================\n", flush=True)
        return result

    def get_screen(self, clear_buffer=False):
        """Get current screen content (decoded)"""
        # Read any pending output first
        self._read_output(timeout=0.005)
        # Decode and strip ANSI codes for easier assertions
        text = self.output_buffer.decode('utf-8', errors='ignore')
        # Clear buffer if requested (for checking current state only)
        if clear_buffer:
            self.output_buffer = b''
        # Remove ANSI escape sequences (comprehensive stripping)
        import re
        # CSI sequences (Control Sequence Introducer) - most common
        text = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', text)
        # OSC sequences (Operating System Command)
        text = re.sub(r'\x1b\][0-9];.*?(\x07|\x1b\\)', '', text)
        # Other escape sequences
        text = re.sub(r'\x1b[=>]', '', text)
        text = re.sub(r'\x1b\([0-9AB]', '', text)
        # Control characters (except newline and tab)
        text = re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f]', '', text)
        # Debug output if env var is set
        if os.environ.get('DEBUG_NVIM_SCREEN'):
            print(f"\n=== SCREEN OUTPUT (accumulated buffer) ===\n{text[-500:]}\n===================\n", flush=True)

        return text

    def assert_visible(self, text):
        """Assert that text is visible on screen"""
        grid = self.get_grid()
        assert text in grid, f"Expected '{text}' in current grid.\nGrid:\n{grid}"

    def assert_not_visible(self, text):
        """Assert that text is NOT visible on screen"""
        grid = self.get_grid()
        assert text not in grid, f"Did not expect '{text}' in current grid.\nGrid:\n{grid}"

    def close(self):
        """Close nvim"""
        if self.master_fd:
            # Send :q!
            self.send_keys(':q!\n')
            time.sleep(0.01)
            try:
                os.close(self.master_fd)
            except:
                pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class TestMakeRunner(unittest.TestCase):
    """E2E tests for make-runner"""

    @classmethod
    def setUpClass(cls):
        """Set up test class with config directory"""
        cls.config_dir = Path.home() / '.config/nvim'

    def test_open_make_runner(self):
        """Test opening make-runner with 'm'"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test Makefile
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text(
                "test: ## Run tests\n"
                "\techo \"testing\"\n"
                "\n"
                "build: ## Build project\n"
                "\techo \"building\"\n"
            )
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                # Press 'm' to open make-runner
                nvim.send_keys('m')
                time.sleep(0.03)
                # Get current grid state (what's actually visible)
                grid = nvim.get_grid()
                # Should see targets in the current screen
                assert 'test' in grid, f"Expected 'test' in grid"
                assert 'build' in grid, f"Expected 'build' in grid"
                assert 'Run tests' in grid, f"Expected 'Run tests' in grid"


    def test_filter_targets(self):
        """Test filtering targets by typing"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text(
                "test: ## Run tests\n"
                "\techo \"testing\"\n"
                "\n"
                "build: ## Build project\n"
                "\techo \"building\"\n"
                "\n"
                "deploy: ## Deploy\n"
                "\techo \"deploying\"\n"
            )
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                # Press 'm' to open make-runner
                nvim.send_keys('m')
                time.sleep(0.05)  # Give more time for UI to open
                # Verify make-runner opened with all targets
                grid = nvim.get_grid()
                assert 'test' in grid and 'build' in grid and 'deploy' in grid, \
                    f"Make-runner should show all targets.\nGrid:\n{grid}"
                # Type "te" to filter
                nvim.send_keys('te')
                time.sleep(0.03)
                # Check current grid - only 'test' should match filter
                grid = nvim.get_grid()
                # After filtering, 'test' should be visible
                assert 'test' in grid, f"Expected 'test' after filtering"
                # build and deploy should NOT appear in filtered view
                assert 'build' not in grid, f"Should not see 'build' after filtering by 'te'"
                assert 'deploy' not in grid, f"Should not see 'deploy' after filtering by 'te'"

    def test_close_with_zero(self):
        """Test closing make-runner with '0'"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text('test: ## Test\n\techo test\n')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                nvim.send_keys('m')
                time.sleep(0.03)
                # Should see make-runner
                grid = nvim.get_grid()
                assert 'test' in grid, f"Expected make-runner with 'test' target"
                # Press 0 to close
                nvim.send_keys('0')
                time.sleep(0.03)
                # Grid should no longer show the make-runner UI
                grid = nvim.get_grid()
                # Floating window border characters or target names shouldn't be visible
                assert 'Test' not in grid and 'test' not in grid.lower(), \
                    f"UI should be closed.\nGrid:\n{grid}"

    def test_close_with_escape(self):
        """Test closing make-runner with ESC"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text('test: ## Test\n\techo test\n')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                nvim.send_keys('m')
                time.sleep(0.03)
                grid = nvim.get_grid()
                assert 'test' in grid, f"Expected make-runner with 'test' target"
                # Press ESC to close
                nvim.send_keys('\x1b')  # ESC
                time.sleep(0.03)
                # Should be closed
                grid = nvim.get_grid()
                assert 'Test' not in grid and 'test' not in grid.lower(), \
                    f"UI should be closed after ESC.\nGrid:\n{grid}"

    def test_navigate_with_ctrl_k(self):
        """Test navigating targets with Ctrl-k"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text(
                "first: ## First target\n"
                "\techo \"1\"\n"
                "\n"
                "second: ## Second target\n"
                "\techo \"2\"\n"
                "\n"
                "third: ## Third target\n"
                "\techo \"3\"\n"
            )
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                nvim.send_keys('m')
                time.sleep(0.02)
                # All targets visible
                nvim.assert_visible('first')
                nvim.assert_visible('second')
                nvim.assert_visible('third')
                # Navigate down with Ctrl-k
                nvim.send_ctrl('k')
                time.sleep(0.01)
                # Should still see all targets (just selection moved)
                nvim.assert_visible('first')
                nvim.assert_visible('second')

    def test_execute_with_number(self):
        """Test executing target with number shortcut"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text(
                "first: ## First target\n"
                "\techo \"first\"\n"
                "\n"
                "second: ## Second target\n"
                "\techo \"second\"\n"
            )
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                # Open make-runner
                nvim.send_keys('m')
                time.sleep(0.03)
                nvim.assert_visible('first')
                nvim.assert_visible('second')
                # Press 1 to execute first target
                nvim.send_keys('1')
                time.sleep(0.05)
                # Should see output terminal with 'first'
                grid = nvim.get_grid()
                self.assertIn('first', grid)

    def test_make_runner_no_makefile(self):
        """Test make-runner behavior with no Makefile"""
        with tempfile.TemporaryDirectory() as tmpdir:
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                # Try to open make-runner
                nvim.send_keys('m')
                time.sleep(0.03)
                # Should show no targets or error message
                grid = nvim.get_grid()
                self.assertTrue('No targets found' in grid or 'Makefile' in grid)

    def test_make_runner_empty_makefile(self):
        """Test make-runner with empty Makefile"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text('')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                nvim.send_keys('m')
                time.sleep(0.03)
                grid = nvim.get_grid()
                self.assertIn('No targets found', grid)

    def test_make_runner_multiple_filters(self):
        """Test filtering multiple times"""
        with tempfile.TemporaryDirectory() as tmpdir:
            makefile = Path(tmpdir) / 'Makefile'
            makefile.write_text(
                "test-unit: ## Unit tests\n"
                "\techo unit\n"
                "\n"
                "test-integration: ## Integration tests\n"
                "\techo integration\n"
                "\n"
                "build: ## Build\n"
                "\techo build\n"
            )
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir)
                nvim.send_keys('m')
                time.sleep(0.03)
                # Type "test" to filter
                nvim.send_keys('test')
                time.sleep(0.03)
                grid = nvim.get_grid()
                # Should see both test targets
                self.assertIn('test-unit', grid)
                self.assertIn('test-integration', grid)
                self.assertNotIn('build', grid)


class TestFileFinder(unittest.TestCase):
    """E2E tests for file-finder"""

    @classmethod
    def setUpClass(cls):
        """Set up test class with config directory"""
        cls.config_dir = Path.home() / '.config/nvim'

    def test_open_file_finder(self):
        """Test opening file-finder with 'o'"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test files
            (Path(tmpdir) / 'fileA.txt').write_text('content A')
            (Path(tmpdir) / 'fileB.txt').write_text('content B')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='fileA.txt')
                time.sleep(0.02)
                # Should see fileA content
                nvim.assert_visible('content A')
                # Press 'O' to open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should see file list
                nvim.assert_visible('fileA')
                nvim.assert_visible('fileB')

    def test_switch_files(self):
        """Test switching between files with file-finder"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'fileA.txt').write_text('content A')
            (Path(tmpdir) / 'fileB.txt').write_text('content B')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='fileA.txt')
                time.sleep(0.02)
                nvim.assert_visible('content A')
                # Open file-finder with 'O' (Shift+O)
                nvim.send_keys('O')
                time.sleep(0.03)
                # Type "fileB" to search
                nvim.send_keys('fileB')
                time.sleep(0.02)
                # Press Enter to open
                nvim.send_keys('\n')
                time.sleep(0.03)
                # Should now see fileB content
                nvim.assert_visible('content B')
                nvim.assert_not_visible('content A')

    def test_file_finder_filter(self):
        """Test filtering files by typing"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'test.txt').write_text('test')
            (Path(tmpdir) / 'build.txt').write_text('build')
            (Path(tmpdir) / 'deploy.txt').write_text('deploy')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='test.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # All files should be visible initially
                grid = nvim.get_grid()
                self.assertIn('test.txt', grid)
                self.assertIn('build.txt', grid)
                self.assertIn('deploy.txt', grid)
                # Type "te" to filter
                nvim.send_keys('te')
                time.sleep(0.03)
                # Only test.txt should match
                grid = nvim.get_grid()
                self.assertIn('test.txt', grid)
                self.assertNotIn('build.txt', grid)
                self.assertNotIn('deploy.txt', grid)

    def test_file_finder_close_with_escape(self):
        """Test closing file-finder with ESC"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'test.txt').write_text('test content')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='test.txt')
                time.sleep(0.02)
                nvim.assert_visible('test content')
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                nvim.assert_visible('test.txt')
                # Close with ESC
                nvim.send_keys('\x1b')
                time.sleep(0.03)
                # Should be back to file content
                nvim.assert_visible('test content')

    def test_file_finder_subdirectories(self):
        """Test file-finder with subdirectories"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'root.txt').write_text('root')
            subdir = Path(tmpdir) / 'subdir'
            subdir.mkdir()
            (subdir / 'nested.txt').write_text('nested')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='root.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should see both root and subdirectory files
                grid = nvim.get_grid()
                self.assertIn('root.txt', grid)
                self.assertIn('nested.txt', grid)

    def test_file_finder_navigate_with_ctrl_k(self):
        """Test navigating files with Ctrl-k"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'first.txt').write_text('1')
            (Path(tmpdir) / 'second.txt').write_text('2')
            (Path(tmpdir) / 'third.txt').write_text('3')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='first.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # All files visible
                nvim.assert_visible('first.txt')
                nvim.assert_visible('second.txt')
                nvim.assert_visible('third.txt')
                # Navigate down with Ctrl-k
                nvim.send_ctrl('k')
                time.sleep(0.01)
                # Should still see all files (just selection moved)
                nvim.assert_visible('first.txt')
                nvim.assert_visible('second.txt')

    def test_file_finder_many_files(self):
        """Test file-finder with many files"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create 10 files
            for i in range(10):
                (Path(tmpdir) / f'file{i:02d}.txt').write_text(f'content {i}')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='file00.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should see file list
                grid = nvim.get_grid()
                self.assertIn('file00.txt', grid)
                # Should see multiple files
                file_count = sum(1 for i in range(10) if f'file{i:02d}.txt' in grid)
                self.assertGreaterEqual(file_count, 5, "Should show multiple files")

    def test_file_finder_empty_directory(self):
        """Test file-finder with no files"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file so nvim has something to open
            (Path(tmpdir) / 'dummy.txt').write_text('x')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='dummy.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should show dummy.txt
                grid = nvim.get_grid()
                self.assertIn('dummy.txt', grid)

    def test_file_finder_special_characters(self):
        """Test file-finder with special characters in filenames"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'file-with-dash.txt').write_text('dash')
            (Path(tmpdir) / 'file_with_underscore.txt').write_text('underscore')
            (Path(tmpdir) / 'file.with.dots.txt').write_text('dots')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='file-with-dash.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # All files should be visible
                grid = nvim.get_grid()
                self.assertIn('file-with-dash.txt', grid)
                self.assertIn('file_with_underscore.txt', grid)
                self.assertIn('file.with.dots.txt', grid)

    def test_file_finder_filter_partial_match(self):
        """Test file-finder fuzzy/partial matching"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'readme.md').write_text('readme')
            (Path(tmpdir) / 'test_file.py').write_text('test')
            (Path(tmpdir) / 'another_test.py').write_text('another')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='readme.md')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Filter with "py" to match .py files
                nvim.send_keys('py')
                time.sleep(0.03)
                grid = nvim.get_grid()
                # Should match .py files
                self.assertIn('test_file.py', grid)
                # Should have filtered out readme.md (or at least not prioritize it)
                self.assertIn('.py', grid)

    def test_file_finder_navigate_and_select(self):
        """Test navigating and selecting with Ctrl-i/k"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'aaa.txt').write_text('aaa content')
            (Path(tmpdir) / 'bbb.txt').write_text('bbb content')
            (Path(tmpdir) / 'ccc.txt').write_text('ccc content')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='aaa.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Navigate down twice
                nvim.send_ctrl('k')
                time.sleep(0.01)
                nvim.send_ctrl('k')
                time.sleep(0.01)
                # Press Enter to select
                nvim.send_keys('\n')
                time.sleep(0.03)
                # Should open one of the files
                grid = nvim.get_grid()
                self.assertTrue('content' in grid)

    def test_file_finder_reopen_after_close(self):
        """Test reopening file-finder after closing it"""
        with tempfile.TemporaryDirectory() as tmpdir:
            (Path(tmpdir) / 'test.txt').write_text('test')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='test.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                nvim.assert_visible('test.txt')
                # Close with ESC
                nvim.send_keys('\x1b')
                time.sleep(0.03)
                # Reopen
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should work again
                nvim.assert_visible('test.txt')

    def test_file_finder_deep_subdirectories(self):
        """Test file-finder with deeply nested directories"""
        with tempfile.TemporaryDirectory() as tmpdir:
            deep_path = Path(tmpdir) / 'a' / 'b' / 'c' / 'd'
            deep_path.mkdir(parents=True)
            (deep_path / 'deep.txt').write_text('deep')
            (Path(tmpdir) / 'root.txt').write_text('root')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='root.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Should see both root and deep files
                grid = nvim.get_grid()
                self.assertIn('root.txt', grid)
                self.assertIn('deep.txt', grid)

    def test_file_finder_lines_limited(self):
        """COMPREHENSIVE: Test exact structure of limited lines with ... indicator"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file with many lines containing 'testword'
            content = '\n'.join([f'testword line {i}' for i in range(10)])
            (Path(tmpdir) / 'many_matches.txt').write_text(content)
            (Path(tmpdir) / 'dummy.txt').write_text('dummy')
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='dummy.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Search for 'testword' which appears 10 times
                nvim.send_keys('testword')
                time.sleep(0.05)
                grid = nvim.get_grid()
                lines = grid.split('\n')
                # Find the line with the filename
                filename_idx = None
                for i, line in enumerate(lines):
                    if 'many_matches.txt' in line:
                        filename_idx = i
                        break
                self.assertIsNotNone(filename_idx, "Should find 'many_matches.txt' in grid")
                # Preemptive check: ensure we have enough lines for the structure
                self.assertGreater(len(lines), filename_idx + 4,
                    f"Should have at least 4 lines after filename. Grid has {len(lines)} lines, filename at {filename_idx}")
                # Check the structure: filename, then exactly 3 matched lines, then "..."
                # Line filename_idx+1 should contain "testword line 0"
                self.assertIn('testword line 0', lines[filename_idx + 1],
                    f"Line after filename should be first match. Got: {lines[filename_idx + 1]}")
                # Line filename_idx+2 should contain "testword line 1"
                self.assertIn('testword line 1', lines[filename_idx + 2],
                    f"Second line should be second match. Got: {lines[filename_idx + 2]}")
                # Line filename_idx+3 should contain "testword line 2"
                self.assertIn('testword line 2', lines[filename_idx + 3],
                    f"Third line should be third match. Got: {lines[filename_idx + 3]}")
                # Line filename_idx+4 should contain "..." (indicating more matches available)
                line_with_dots = lines[filename_idx + 4].strip()
                # Check if this line is "..." or contains "..."
                if '...' in line_with_dots and 'testword' not in line_with_dots:
                    self.assertTrue(line_with_dots.startswith('...') or '...' in line_with_dots,
                        f"Fourth line after filename should be '...'. Got: {lines[filename_idx + 4]}")
                # Verify we don't show line 9 (proves limiting works)
                self.assertNotIn('testword line 9', grid, "Should not show line 9 (only first 3 lines)")

    def test_file_finder_plus_minus_keys(self):
        """COMPREHENSIVE: Test ≠/– (warning not regular -) keys adjust line count per file"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file with many matching lines
            content = '\n'.join([f'XYZABC number {i}' for i in range(10)])
            (Path(tmpdir) / 'data.txt').write_text(content)
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='data.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Search for 'XYZABC'
                nvim.send_keys('XYZABC')
                time.sleep(0.05)
                grid = nvim.get_grid()
                lines = grid.split('\n')
                # Find filename and count matched lines after it
                filename_idx = next((i for i, l in enumerate(lines) if 'data.txt' in l), None)
                self.assertIsNotNone(filename_idx, "Should find 'data.txt' in grid")
                # Count lines with "XYZABC number" after filename (before next file or empty)
                initial_count = 0
                for i in range(filename_idx + 1, len(lines)):
                    if 'XYZABC number' in lines[i]:
                        initial_count += 1
                    elif lines[i].strip() and not lines[i].strip().startswith('~'):
                        # Hit another file or non-match content, stop counting
                        break
                self.assertGreater(initial_count, 0, "Should show some matched lines initially")
                # Press ≠ (could link to Ctrl+= in your term) to increase lines (give UI time to update)
                nvim.send_keys('≠')
                time.sleep(0.1)  # More time for grid to re-render
                grid_after_plus = nvim.get_grid()
                lines_after_plus = grid_after_plus.split('\n')
                # Count again after pressing +
                filename_idx_plus = next((i for i, l in enumerate(lines_after_plus) if 'data.txt' in l), None)
                self.assertIsNotNone(filename_idx_plus, "Should still find 'data.txt' after +")
                plus_count = 0
                for i in range(filename_idx_plus + 1, len(lines_after_plus)):
                    if 'XYZABC number' in lines_after_plus[i]:
                        plus_count += 1
                    elif lines_after_plus[i].strip() and not lines_after_plus[i].strip().startswith('~'):
                        break
                # Check precisely +1 (should increase by exactly 1)
                self.assertEqual(plus_count, initial_count + 1,
                    f"After +: should show exactly initial+1 lines. Initial={initial_count}, After +={plus_count}")
                # Press – (could link to Ctrl+- in your term - warning not regular -)(Ctrl+) to decrease lines
                nvim.send_keys('–')
                time.sleep(0.1)  # More time for grid to re-render
                grid_after_minus = nvim.get_grid()
                lines_after_minus = grid_after_minus.split('\n')
                # Count again after pressing - (should be back to initial_count)
                filename_idx_minus = next((i for i, l in enumerate(lines_after_minus) if 'data.txt' in l), None)
                self.assertIsNotNone(filename_idx_minus, "Should still find 'data.txt' after -")
                minus_count = 0
                for i in range(filename_idx_minus + 1, len(lines_after_minus)):
                    if 'XYZABC number' in lines_after_minus[i]:
                        minus_count += 1
                    elif lines_after_minus[i].strip() and not lines_after_minus[i].strip().startswith('~'):
                        break
                # Check precisely went back to initial (should be exactly initial_count)
                self.assertEqual(minus_count, initial_count,
                    f"After -: should show exactly initial count. Initial={initial_count}, After -={minus_count}")
                # Press – (Ctrl+-) again to go to initial-1
                nvim.send_keys('–')
                time.sleep(0.1)  # More time for grid to re-render
                grid_after_minus2 = nvim.get_grid()
                lines_after_minus2 = grid_after_minus2.split('\n')
                filename_idx_minus2 = next((i for i, l in enumerate(lines_after_minus2) if 'data.txt' in l), None)
                self.assertIsNotNone(filename_idx_minus2, "Should still find 'data.txt' after second -")
                minus2_count = 0
                for i in range(filename_idx_minus2 + 1, len(lines_after_minus2)):
                    if 'XYZABC number' in lines_after_minus2[i]:
                        minus2_count += 1
                    elif lines_after_minus2[i].strip() and not lines_after_minus2[i].strip().startswith('~'):
                        break
                # Check we went to initial-1 (or stayed at minimum of 1)
                self.assertEqual(minus2_count, max(1, initial_count - 1),
                    f"After second -: should show initial-1 (or min 1). Initial={initial_count}, After second -={minus2_count}")

    def test_file_finder_no_dots_when_few_lines(self):
        """COMPREHENSIVE: Test that '...' does NOT appear when showing all matches"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file with only 2 lines containing 'match' (less than default 3)
            content = 'line 1 with match\nline 2 with match'
            (Path(tmpdir) / 'few_matches.txt').write_text(content)
            with NvimTerminal(self.config_dir) as nvim:
                nvim.start(cwd=tmpdir, filename='few_matches.txt')
                time.sleep(0.02)
                # Open file-finder
                nvim.send_keys('O')
                time.sleep(0.03)
                # Search for 'match'
                nvim.send_keys('match')
                time.sleep(0.03)
                grid = nvim.get_grid()
                lines = grid.split('\n')
                # Find the filename
                filename_idx = next((i for i, l in enumerate(lines) if 'few_matches.txt' in l), None)
                self.assertIsNotNone(filename_idx, "Should find 'few_matches.txt' in grid")
                # Check the structure: filename, then 2 matched lines, NO "..."
                # Line filename_idx+1 should contain "line 1 with match"
                if filename_idx + 1 < len(lines):
                    self.assertIn('line 1 with match', lines[filename_idx + 1],
                        f"First line after filename should be first match. Got: {lines[filename_idx + 1]}")
                # Line filename_idx+2 should contain "line 2 with match"
                if filename_idx + 2 < len(lines):
                    self.assertIn('line 2 with match', lines[filename_idx + 2],
                        f"Second line after filename should be second match. Got: {lines[filename_idx + 2]}")
                # Simple loop: check that NO line after filename contains "..."
                for i in range(filename_idx + 1, len(lines)):
                    if '...' in lines[i]:
                        self.fail(
                            f"Found '...' in line {i} when there are only 2 matches (no truncation needed). "
                            f"Line: {lines[i]}"
                        )

    def test_file_finder_history_ranking(self):
        """COMPREHENSIVE: Test history-based ranking for files with equal scores"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create 3 files with identical content (same score when searched)
            content = 'common keyword here\nanother line\n'
            (Path(tmpdir) / 'file_a.txt').write_text(content)
            (Path(tmpdir) / 'file_b.txt').write_text(content)
            (Path(tmpdir) / 'file_c.txt').write_text(content)
            with NvimTerminal(self.config_dir) as nvim:
                # Open files in specific order to build history: a -> b -> c
                # Start with file_a to establish initial file tree
                nvim.start(cwd=tmpdir, filename='file_a.txt')
                time.sleep(0.05)
                # Open file_b and file_c to build history
                # Use uppercase 'O' for FILE SEARCH mode (not history mode)
                for filename in ['file_b.txt', 'file_c.txt']:
                    nvim.send_keys('\x1b')  # Escape to ensure normal mode
                    time.sleep(0.03)
                    nvim.send_keys('O')  # Open file-finder (file search mode)
                    time.sleep(0.08)
                    nvim.send_keys(filename)
                    time.sleep(0.08)
                    nvim.send_keys('\n')  # Select file
                    time.sleep(0.1)  # Wait for file to open
                # Ensure we're in normal mode and file-finder is closed
                nvim.send_keys('\x1b')
                time.sleep(0.05)
                # Now use uppercase 'O' for FILE SEARCH mode and search for 'file_'
                # All 3 files match the filename pattern with equal score
                # History ranking should make them appear: c, b, a (most recent first)
                nvim.send_keys('O')
                time.sleep(0.1)
                nvim.send_keys('file_')
                time.sleep(0.15)
                grid = nvim.get_grid()
                lines = grid.split('\n')
                # Find positions of each file in the results
                file_a_idx = next((i for i, l in enumerate(lines) if 'file_a.txt' in l), None)
                file_b_idx = next((i for i, l in enumerate(lines) if 'file_b.txt' in l), None)
                file_c_idx = next((i for i, l in enumerate(lines) if 'file_c.txt' in l), None)
                # All files should be present
                self.assertIsNotNone(file_a_idx, "file_a.txt should appear in results")
                self.assertIsNotNone(file_b_idx, "file_b.txt should appear in results")
                self.assertIsNotNone(file_c_idx, "file_c.txt should appear in results")
                # Verify history-based ranking: most recent (c) should be first
                # Order should be: file_c, file_b, file_a (reverse of opening order)
                self.assertLess(
                    file_c_idx,
                    file_b_idx,
                    f"file_c.txt (most recent) should appear before file_b.txt. "
                    f"Got c at {file_c_idx}, b at {file_b_idx}"
                )
                self.assertLess(
                    file_b_idx,
                    file_a_idx,
                    f"file_b.txt should appear before file_a.txt (least recent). "
                    f"Got b at {file_b_idx}, a at {file_a_idx}"
                )


if __name__ == '__main__':
    unittest.main(verbosity=2)
