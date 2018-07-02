
luash = require "syscalls"
lpeg = require "lpeg"
pretty = require 'pl.pretty'

Cmd = {}
Cmd.mt = {}

built_ins = {}

function register_built_in(func_name, func)
	built_ins[func_name] = func
end

function get_built_in(func_name)
	return built_ins[func_name]
end

function capture_program(program_name, ...)
	local built_in = get_built_in(program_name)
	if built_in == nil then
		return make_cmd(
			{ type="exec"
			, command=program_name
			, argv={program_name, ...}
			})
	end
	local func = built_in(...)
	return func
end

function capture_operator(lhs, op, rhs)
	local ops = 
	{
		["|"] = "pipe",
		["&&"] = "and",
		[";"] = "concat"
	}
	return Cmd.bin_op(ops[op], lhs, rhs)
end

function sh(cmd)
	whitespace = lpeg.S(" \t\n");
	operator = whitespace^0 * ((lpeg.P("|") + lpeg.P("&&") + lpeg.P(";")) / tostring);
	word = whitespace^0 * ((lpeg.R("az") + lpeg.R("AZ") + lpeg.S("-\"=./_") + lpeg.R("09"))^1 / tostring);
	program = word^1 / capture_program;
	shell = lpeg.P({
		"command",
		command = ((program * operator * lpeg.V("command")) / capture_operator + program),
	})
	local result = shell:match(cmd)
	return result
end

function change_fd(initial_fd, target_fd)
	if initial_fd ~= target_fd then
		luash.dup2(initial_fd, target_fd)
		luash.close(initial_fd)
	end
end

function make_fd_stdin(fd)
	change_fd(fd, STDIN)
end

function make_fd_stdout(fd)
	change_fd(fd, STDOUT)
end

function is_cmd(maybe_cmd)
	return getmetatable(maybe_cmd) == Cmd.mt
end

function assert_cmd(maybe_cmd)
	if not is_cmd(maybe_cmd) then
		error("Cmd expected.")
	end
end

function make_cmd(cmd)
	setmetatable(cmd, Cmd.mt)
	return cmd;
end


function convert_to_cmd(obj)
	local function cmd_to_cmd(cmd)
		if is_cmd(cmd) then return cmd end
	end
	local function func_to_cmd(func)
		if type(func) == "function" then
			return make_cmd(
				{ type="function"
				, func=func
				, mutates=false
				})
		end
	end
	local function string_to_cmd(args)
		if type(args) ~= "string" then
			return
		end
		local argv = {}
		for arg in args:gmatch("%S+") do
			table.insert(argv, arg)
		end
		return make_cmd(
			{ type="exec"
			, command=argv[1]
			, argv=argv
			})
	end
	local converters = 
	{ cmd_to_cmd
	, func_to_cmd
	, string_to_cmd
	}
	local result = nil
	for _, converter in ipairs(converters) do
		result = converter(obj)
		if result ~= nil then
			assert_cmd(result)
			return result
		end
	end
	error ("Unable to convert to cmd")
end

function cmd(args)
	return convert_to_cmd(args)
end

function Cmd.run_exec(cmd, ifd, ofd)
	local pid = luash.fork()
	if pid == 0 then
		make_fd_stdin(ifd)
		make_fd_stdout(ofd)
		luash.execve(cmd.command, cmd.argv)
	else
		local pid, exit_status = luash.waitpid(pid, 0)
		return exit_status
	end
end

function Cmd.run_function(cmd, ifd, ofd)
	if not (cmd.mutates) then
		local pid = luash.fork()
		if pid == 0 then
			make_fd_stdin(ifd)
			make_fd_stdout(ofd)
			cmd.func()
			luash.exit(0)
		else
			local pid, exit_status = luash.waitpid(pid, 0)
			return exit_status
		end
	else
		cmd.func()
	end
end

function Cmd.run_concat(cmd, ifd, ofd)
	Cmd.run_cmd(cmd.cmd1, ifd, ofd)
	return Cmd.run_cmd(cmd.cmd2, ifd, ofd)
end

function Cmd.run_and(cmd, ifd, ofd)
	local exit_status = Cmd.run_cmd(cmd.cmd1, ifd, ofd)
	if exit_status == 0 then
		return Cmd.run_cmd(cmd.cmd2, ifd, ofd)
	end
	return exit_status
end

function Cmd.run_pipe(cmd, ifd, ofd)
	local p1, p2 = luash.pipe()
	local pid = luash.fork()
	if pid == 0 then
		local status = Cmd.run_cmd(cmd.cmd1, ifd, p2)
		luash.exit(status);
	else
		luash.waitpid(pid, 0)
		luash.close(p2)
		local status = Cmd.run_cmd(cmd.cmd2, p1, ofd)
		return status
	end
end

STDIN 	= 0
STDOUT 	= 1

function Cmd.run_cmd(cmd, ifd, ofd)
	local cmd_runners = 
	{ ["exec"] = Cmd.run_exec
	, ["concat"] = Cmd.run_concat
	, ["and"] = Cmd.run_and
	, ["pipe"] = Cmd.run_pipe
	, ["function"] = Cmd.run_function
	}
	for type, runner in pairs(cmd_runners) do
		if cmd.type == type then
			return runner(cmd, ifd, ofd)
		end
	end
	error ("Unknown command type")
end

function Cmd.execute(cmd)
	Cmd.run_cmd(cmd, STDIN, STDOUT)
	return ""
end

function Cmd.arg(cmd, argv_string)
	if cmd.type ~= "exec" then
		error ("Cannot modify argument list if command does not invoke program")
	end
	local argv = {}
	for _, arg in ipairs(cmd.argv) do
		table.insert(argv, arg)
	end
	for arg in argv_string:gmatch("%S+") do
		table.insert(argv, arg)
	end
	return make_cmd({type="exec", command = cmd.command, argv = argv})
end

function Cmd.bin_op(type, cmd1, cmd2)
	cmd1 = convert_to_cmd(cmd1)
	cmd2 = convert_to_cmd(cmd2)
	return make_cmd(
		{ type=type
		, cmd1=cmd1
		, cmd2=cmd2
		})
end

function Cmd.concat(cmd1, cmd2)
	return Cmd.bin_op("concat", cmd1, cmd2)
end

function Cmd.and_op(cmd1, cmd2)
	return Cmd.bin_op("and", cmd1, cmd2)
end

function Cmd.pipe_op(cmd1, cmd2)
	return Cmd.bin_op("pipe", cmd1, cmd2)
end

Cmd.mt.__tostring = Cmd.execute
Cmd.mt.__concat = Cmd.concat
Cmd.mt.__add = Cmd.and_op
Cmd.mt.__call = Cmd.arg
Cmd.mt.__bor = Cmd.pipe_op


function getcwd()
	return luash.getcwd()
end

function lua_pwd()
	print(getcwd())
end

function lua_cd(path)
	local func = function() luash.chdir(path) end
	return make_cmd(
	{ type="function"
	, func=func
	, mutates=true
	})
end

function lua_ls(path)
	return convert_to_cmd(function ()
		if path == nil then
			path = "."
		end
		fd = luash.open(path);
		if fd == -1 then
			print("Failed to open dir")
			return
		end
		entries = luash.getdirentries(fd)
		for index, entry in ipairs(entries) do
			print (entry.d_name)
		end
		luash.close(fd);
	end)
end

function lua_grep(pattern)
	return convert_to_cmd(function ()
		for line in io.stdin:lines() do
			if string.match(line, pattern) ~= nil then
				print(line)
			end
		end
	end)
end

function lua_echo(str)
	return convert_to_cmd(function()
		print(str)
	end)
end

function lua_cat(path)
	local file = io.stdin
	if path ~= nil then
		file = io.open(path, "r")
		if file == nil then
			return
		end
	end
	return convert_to_cmd(function ()
		for line in file:lines() do
			print(line)
		end
	end)
end

function lua_to_file(path)
	return convert_to_cmd( function()
		local file = io.open(path, "w")
		if file == nil then
			return
		end
		for line in io.stdin:lines() do
			file:write(line .. '\n');
		end
	end)
end

register_built_in("cat", lua_cat)
register_built_in("to_file", lua_to_file)
register_built_in("echo", lua_echo)
register_built_in("lls", lua_ls)
register_built_in("lgrep", lua_grep)
register_built_in("cd", lua_cd)