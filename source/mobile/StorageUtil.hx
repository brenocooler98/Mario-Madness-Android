package mobile;

#if android

import androidmanager.content.Context;
import haxe.io.Path;
import lime.system.System;
import sys.FileSystem;
import sys.io.File;

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

	public static function getCachePath():String
	{
		var path:Null<String> = Context.getCacheDir();
		if (path == null || path.length == 0)
			path = getStoragePath() + 'cache/';
		return Path.addTrailingSlash(path);
	}

	public static function cacheAsset(id:String, name:String):String
	{
		try
		{
			var path:String = getCachePath() + name;
			var marker:String = path + '.build';
			if (FileSystem.exists(path) && FileSystem.exists(marker) && File.getContent(marker) == BuildInfo.id)
				return path;

			if (!openfl.utils.Assets.exists(id))
				return id;

			var directory:String = Path.directory(path);
			if (!FileSystem.exists(directory))
				FileSystem.createDirectory(directory);

			File.saveBytes(path, openfl.utils.Assets.getBytes(id));
			File.saveContent(marker, BuildInfo.id);
			return path;
		}
		catch (e:Dynamic)
		{
			return id;
		}
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
