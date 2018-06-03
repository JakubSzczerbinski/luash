#include <lua.hpp>
#include <unistd.h>
#include <cstring>
#include <cerrno>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <limits.h>
#include <stdlib.h>
#include <poll.h>

extern "C"
{

static int lua_fork(lua_State* L)
{
	pid_t result = fork();
	lua_pushnumber(L, result);
	return 1;
}

#define ARG_MAX 65536

static int lua_execve(lua_State* L)
{
	int result;
	int i = 0;

	const char* path = luaL_checkstring(L, 1);
	char** argv = (char**)malloc(sizeof(char*) * ARG_MAX);

	if (not lua_istable(L, 2))
	{
		result = -1;
		goto end;
	}

	lua_pushnil(L);
	while (lua_next(L,-2) != 0) {
		if (i >= ARG_MAX)
		{
			result = -1;
			goto end;
		}
		if (not lua_isstring(L, -1))
		{
			result = -1;
			goto end;
		}

		const char* str = lua_tostring(L,-1);
		argv[i] = (char*)malloc(sizeof(char) * (strlen(str) + 1));
		strcpy(argv[i], str);

		lua_pop(L,1);
		i++;
	}
	argv[i] = NULL;

	result = execvpe(path, argv, environ);
	if (result != 0) result = errno;
end:
	lua_pushnumber(L, result);
	free(argv);
	return 1;
}

static int lua_waitpid(lua_State* L)
{
	pid_t pid = luaL_checkinteger(L, 1);
	int wstatus;
	int options = luaL_checkinteger(L, 2);
	int result = waitpid(pid, &wstatus, options);
	lua_pushnumber(L, result);
	lua_pushnumber(L, wstatus);
	return 2;
}

static int lua_pipe(lua_State* L)
{
	int fd[2];
	int result = pipe(fd);
	lua_pushnumber(L, fd[0]);
	lua_pushnumber(L, fd[1]);
	lua_pushnumber(L, result);
	return 3;
}

static int lua_close_fd(lua_State* L)
{
	int fd = luaL_checkinteger(L, 1);
	int result = close(fd);
	lua_pushnumber(L, result);
	return 1;
}

static int lua_dup2(lua_State* L)
{
	int fd = luaL_checkinteger(L, 1);
	int fd2 = luaL_checkinteger(L, 2);
	int result = dup2(fd, fd2);
	lua_pushnumber(L, result);
	return 1;
}

static int lua_poll(lua_State* L)
{
	int timeout = luaL_checkinteger(L, 2);
	int nfds = lua_rawlen(L,1);

	if (not lua_istable(L, 2))
	{
		lua_pushinteger(L, 0);
		lua_pushinteger(L, 1);
		return 2;
	}

	int i = 0;
	struct pollfd* fds = (struct pollfd*)malloc(nfds * sizeof(struct pollfd));
	while (lua_next(L,-2) != 0) {
		lua_getfield(L, -1, "fd");
		fds[i].fd = luaL_checkinteger(L, 1);
		lua_getfield(L, -1, "events");
		fds[i].events = luaL_checkinteger(L, 1);
		lua_getfield(L, -1, "revents");
		fds[i].revents = luaL_checkinteger(L, 1);
	}
		
	int result = poll(fds, nfds, 0);
	lua_pushinteger(L, result);
	lua_pushinteger(L, 0);
	return 2;
}

static int lua_exit(lua_State* L)
{
	int status = luaL_checkinteger(L, 1);
	exit(status);
	return 0;
}

static const struct luaL_Reg luash[] = 
{
	{"execve", lua_execve},
	{"fork", lua_fork},
	{"waitpid", lua_waitpid},
	{"pipe", lua_pipe},
	{"close", lua_close_fd},
	{"dup2", lua_dup2},
	{"exit", lua_exit},
	{"poll", lua_poll},
	{NULL, NULL}
};

extern int luaopen_luash (lua_State* L)
{
	luaL_newlib(L, luash);
	return 1;
}

}
