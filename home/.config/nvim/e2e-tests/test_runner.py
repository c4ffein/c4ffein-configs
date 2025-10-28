#!/usr/bin/env python3
"""
E2E test runner for Neovim config
Pure Python stdlib - uses pty to drive real nvim instance

Usage:
  python3 e2e-tests/test_runner.py               # Run all tests
  DEBUG_NVIM_SCREEN=1 python3 e2e-tests/test_runner.py  # Debug mode (show screen output)
"""

import os
import pty
import select
import subprocess
import tempfile
import time
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
        """Send Ctrl+key combination"""
        # Ctrl+key is key code minus 64
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


class TestMakeRunner:
    """E2E tests for make-runner"""

    def __init__(self, config_dir):
        self.config_dir = config_dir

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
                print("✓ test_open_make_runner passed")

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
                print("✓ test_filter_targets passed")

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
                print("✓ test_close_with_zero passed")

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
                print("✓ test_close_with_escape passed")

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
                print("✓ test_navigate_with_ctrl_k passed")


class TestFileFinder:
    """E2E tests for file-finder"""

    def __init__(self, config_dir):
        self.config_dir = config_dir

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
                print("✓ test_open_file_finder passed")

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
                print("✓ test_switch_files passed")


def run_all_tests():
    """Run all test suites"""
    config_dir = Path.home() / '.config/nvim'
    print("Running E2E tests for Neovim config (real terminal mode)...\n")
    # Make-runner tests
    print("=== Make-runner tests ===")
    make_tests = TestMakeRunner(config_dir)
    make_tests.test_open_make_runner()
    make_tests.test_filter_targets()
    make_tests.test_close_with_zero()
    make_tests.test_close_with_escape()
    make_tests.test_navigate_with_ctrl_k()
    # File-finder tests
    print("\n=== File-finder tests ===")
    file_tests = TestFileFinder(config_dir)
    file_tests.test_open_file_finder()
    file_tests.test_switch_files()
    print("\n✅ All tests passed!")


if __name__ == '__main__':
    run_all_tests()
