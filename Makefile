

syscalls: syscalls.c
	gcc syscalls.c -shared -o syscalls.so -fPIC -llua5.3 -I/usr/include/lua5.3
