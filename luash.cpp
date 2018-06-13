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
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>


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

static int lua_getcwd(lua_State* L)
{
	char* buff = (char*)malloc(sizeof(char) * 4096);
	getcwd(buff, 4096);
	lua_pushstring(L, buff);
	free(buff);
	return 1;
}

static int lua_chdir(lua_State* L)
{
	const char* path = luaL_checkstring(L, 1);
	int result = chdir(path);
	lua_pushinteger(L, result);
	return 1;
}

static int lua_getdirentries(lua_State* L)
{
	int fd = luaL_checkinteger(L, 1);
	char* buf = (char*)malloc(sizeof(char) * 4096);
	off_t base_p = 0;
	size_t size_read = 0;
	struct dirent *dir;
	lua_createtable(L, 0, 0);
	int i = 1;
	do
	{
		size_read = getdirentries(fd, buf, 4096, &base_p);
	    dir = (struct dirent *)buf;
	    while ((char *)dir < buf + size_read) {
			lua_pushinteger(L, i++);
	    	lua_createtable(L, 0, 4);

			lua_pushstring(L, "d_type");
			lua_pushinteger(L, dir->d_type);
			lua_settable(L, -3);

			lua_pushstring(L, "d_ino");
			lua_pushinteger(L, dir->d_ino);
			lua_settable(L, -3);

			lua_pushstring(L, "d_off");
			lua_pushinteger(L, dir->d_off);
			lua_settable(L, -3);

			lua_pushstring(L, "d_name");
			lua_pushstring(L, dir->d_name);
			lua_settable(L, -3);

			lua_settable(L, -3);
      		dir = (struct dirent *)((char *)dir + dir->d_reclen);
    	}
	} while (size_read > 0); 
	return 1;
}

static int lua_open(lua_State* L)
{
	const char* path = luaL_checkstring(L, 1);
	int fd = open(path, 0);
	lua_pushinteger(L, fd);
	return 1;
}

static const struct luaL_Reg luash[] = 
{
	{"getcwd", lua_getcwd},
	{"chdir", lua_chdir},
	{"execve", lua_execve},
	{"fork", lua_fork},
	{"waitpid", lua_waitpid},
	{"pipe", lua_pipe},
	{"close", lua_close_fd},
	{"dup2", lua_dup2},
	{"exit", lua_exit},
	{"poll", lua_poll},
	{"getdirentries", lua_getdirentries},
	{"open", lua_open},
	{NULL, NULL}
};

extern int luaopen_luash (lua_State* L)
{
	luaL_newlib(L, luash);
	return 1;
}

}
