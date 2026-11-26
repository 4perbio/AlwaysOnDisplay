// Runs the Lua test suite with fengari (a Lua 5.3 VM in JavaScript), so no
// system Lua install is needed. Usage: npm test
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.resolve(__dirname, "..").split(path.sep).join("/");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring("ROOT"));

// fengari has no io library; READ_FILE(path) returns a file's text.
lua.lua_pushjsfunction(L, (L) => {
  const file = lua.lua_tojsstring(L, 1);
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(file, "utf8")));
  return 1;
});
lua.lua_setglobal(L, to_luastring("READ_FILE"));

if (lauxlib.luaL_dofile(L, to_luastring(root + "/tests/run.lua")) !== lua.LUA_OK) {
  console.error(lua.lua_tojsstring(L, -1));
  process.exit(1);
}
