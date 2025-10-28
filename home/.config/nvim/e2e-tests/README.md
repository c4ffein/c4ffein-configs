# E2E Tests

End-to-end tests for Neovim config using pure Python stdlib (no dependencies).

## Philosophy

- **No dependencies**: Pure Python 3 standard library
- **Communication via files**: nvim writes state to temp files, Python reads and asserts
- **Subprocess-based**: Python spawns headless nvim instances
- **E2E focused**: Tests full workflows, not individual functions

## Running Tests
`python3 e2e-tests/test_runner.py  # Run all tests`

## How It Works
1. **Python orchestrates**: Creates temp dirs, Makefiles, runs nvim
2. **Nvim executes**: Runs in headless mode with Lua commands
3. **File communication**: Nvim writes results to temp files
4. **Python asserts**: Reads files and checks expectations

## Example Test Flow
```python
# 1. Setup
with tempfile.TemporaryDirectory() as tmpdir:
    makefile = Path(tmpdir) / 'Makefile'
    makefile.write_text('test: ## Test\\n\\techo test\\n')
    # 2. Run nvim with commands
    lua_code = f'cd {tmpdir}; require("make-runner").open()'
    stdout, stderr, code = nvim.run_lua(lua_code)
    # 3. Check results
    assert code == 0
    assert "expected output" in stdout
```

## Limitations

- **No full UI testing**: Headless mode limits what we can test
- **Timing sensitive**: Some tests use `vim.wait()` for async operations
- **File-based assertions**: Can't easily check live buffer state

## Future Improvements

- Add more file-finder tests
- Test colorscheme loading
- Test keybind configurations
- Add performance benchmarks
