package mobile;

#if android

import androidmanager.content.Context;
import haxe.io.Path;
import lime.system.System;
import sys.FileSystem;

class StorageUtil
{
	public static function getStoragePath():String
	{
		var path:Null<String> = Context.getExternalFilesDir();
		if (path == null || path.length == 0)
			path = Context.getFilesDir();
		if (path == null || path.length == 0)
			path = System.applicationStorageDirectory;
		return Path.addTrailingSlash(path);
	}

	public static function getCrashPath():String
	{
		var path:String = getStoragePath() + 'crash/';
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
		return path;
	}
}
#end
