package mobile;

#if android
import androidmanager.callback.Callback;
import androidmanager.content.Storage;
import androidmanager.os.Device;
import androidmanager.os.Environment;
import flixel.FlxG;
import flixel.FlxState;
import haxe.Timer;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;

@:cppFileCode('
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>

static char mm_session_path[1024];

static void mm_write(int fd, const char* text)
{
	if (text)
		write(fd, text, strlen(text));
}

static void mm_signal_handler(int sig, siginfo_t* info, void* context)
{
	static volatile int handling = 0;
	if (!handling)
	{
		handling = 1;
		int fd = open(mm_session_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
		if (fd >= 0)
		{
			char line[160];
			snprintf(line, sizeof(line), "native crash: signal %d (%s) at %p\\n", sig, strsignal(sig), info ? info->si_addr : 0);
			mm_write(fd, line);
			Array<String> stack = __hxcpp_get_call_stack(false);
			if (stack.mPtr)
			{
				for (int i = 0; i < stack->length; i++)
				{
					mm_write(fd, "  at ");
					mm_write(fd, stack[i].utf8_str());
					mm_write(fd, "\\n");
				}
			}
			close(fd);
		}
	}
	signal(sig, SIG_DFL);
	raise(sig);
}

static void mm_install_handlers(const char* path)
{
	strncpy(mm_session_path, path, sizeof(mm_session_path) - 1);
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_sigaction = mm_signal_handler;
	action.sa_flags = SA_SIGINFO | SA_ONSTACK;
	int signals[] = {SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGTRAP};
	for (int i = 0; i < 6; i++)
		sigaction(signals[i], &action, NULL);
}
')
class SessionLog
{
	static var output:FileOutput;
	static var startTime:Float = 0;

	public static function init():Void
	{
		if (output != null)
			return;

		var path:String = StorageUtil.getStoragePath() + 'session.txt';
		exportPrevious(path);

		try
		{
			output = File.write(path, false);
		}
		catch (e:Dynamic)
		{
			output = null;
			return;
		}

		startTime = Timer.stamp();
		var nativePath:String = path;
		untyped __cpp__('mm_install_handlers({0}.utf8_str())', nativePath);
		var build = Device.name;
		mark('start ' + lime.app.Application.current.meta.get('version') + ' build ' + BuildInfo.id + ' device ' + build);

		FlxG.signals.preStateCreate.add(function(state:FlxState) mark('create ' + Type.getClassName(Type.getClass(state))));
		FlxG.signals.postStateSwitch.add(function() mark('ready ' + Type.getClassName(Type.getClass(FlxG.state))));
		Callback.onPause.add(function() mark('paused'));
		Callback.onResume.add(function() mark('resumed'));
		Callback.onLowMemory.add(function() mark('low memory'));
		Callback.onTrimMemory.add(function(level) mark('trim memory ' + Std.string(level)));
	}

	public static function mark(text:String):Void
	{
		if (output == null)
			return;

		try
		{
			output.writeString('[' + Std.string(Math.round((Timer.stamp() - startTime) * 1000) / 1000) + 's] [' + memory() + '] ' + text + '\n');
			output.flush();
		}
		catch (e:Dynamic) {}
	}

	static function memory():String
	{
		var haxe:Int = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 1048576);
		var info = null;
		try
		{
			info = Device.getMemoryInfo();
		}
		catch (e:Dynamic) {}

		if (info == null)
			return 'haxe ' + haxe + 'MB';

		return 'haxe ' + haxe + 'MB, free ' + Math.round(info.available / 1048576) + '/' + Math.round(info.total / 1048576) + 'MB' + (info.lowMemory ? ', LOW' : '');
	}

	static function exportPrevious(path:String):Void
	{
		try
		{
			if (!FileSystem.exists(path))
				return;

			var previous:String = File.getContent(path);
			var lines:Array<String> = StringTools.trim(previous).split('\n');
			var last:String = lines.length > 0 ? lines[lines.length - 1] : '';
			if (previous.length == 0 || StringTools.endsWith(last, 'paused'))
				return;

			var report:String = '=== Session ===\n' + previous + '\n=== Logcat ===\n' + Environment.dumpSystemLogs();
			var name:String = 'session-' + Date.now().getTime() + '.txt';
			var reportPath:String = StorageUtil.getCrashPath() + name;
			File.saveContent(reportPath, report);
			Storage.saveToDownloads(reportPath, 'MarioMadness', name);
		}
		catch (e:Dynamic) {}
	}
}
#end
