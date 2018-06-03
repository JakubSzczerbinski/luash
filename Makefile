

luash: luash.cpp
	g++ luash.cpp -shared -o luash.so -fPIC -llua5.3 -I/usr/include/lua5.3
