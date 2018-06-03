

luash = require "luash"

Cmd = {}
Cmd.mt = {}

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
				})
		end
	end
	local function string_to_cmd(str)
		if type(str) == "string" then
			return cmd(str)
		end
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

ls = cmd("/bin/ls")
tee = cmd("/usr/bin/tee")
gcc = cmd("/usr/bin/gcc")
