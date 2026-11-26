// Runs the Lua test suite with fengari (a Lua 5.3 VM in JavaScript), so no
// system Lua install is needed. Usage: npm test
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.resolve(__dirname, "..").split(path.sep).join("/");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring("ROOT"));

if (lauxlib.luaL_dofile(L, to_luastring(root + "/tests/run.lua")) !== lua.LUA_OK) {
  console.error(lua.lua_tojsstring(L, -1));
  process.exit(1);
}
