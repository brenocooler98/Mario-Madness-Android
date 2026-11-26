package;

class CppAPI
{
	public static function obtainRAM():Int
	{
		#if windows
		return WindowsData.obtainRAM();
		#else
		return 0;
		#end
	}

	public static function darkMode()
	{
		#if windows
		WindowsData.setWindowColorMode(DARK);
		#end
	}

	public static function lightMode()
	{
		#if windows
		WindowsData.setWindowColorMode(LIGHT);
		#end
	}

	public static function setWindowOppacity(a:Float)
	{
		#if windows
		WindowsData.setWindowAlpha(a);
		#end
	}

	public static function _setWindowLayered()
	{
		#if windows
		WindowsData._setWindowLayered();
		#end
	}

	public static function setWallpaper(path:String)
	{
		#if windows
		if(path == 'old') {
			if(Wallpaper.oldWallpaper != null) {
			path = Wallpaper.oldWallpaper;
			}else{
				return;
			}}
		Wallpaper.setWallpaper(path);
		#end
	}

	public static function setOld()
	{
		#if windows
		Wallpaper.setOld();
		#end
	}

	public static function hideTaskbar()
	{
		#if windows
		WindowsData.hideTaskbar();
		#end
	}

	public static function restoreTaskbar()
	{
		#if windows
		WindowsData.restoreTaskbar();
		#end
	}

	public static function hideWindows()
	{
		#if windows
		WindowsData.hideWindows();
		#end
	}

	public static function restoreWindows()
	{
		#if windows
		WindowsData.restoreWindows();
		#end
	}

	public static function setTransparency(winName:String, color:Int)
	{
		#if windows
		Transparency.setTransparency(winName, color);
		#end
	}
	
	public static function removeWindowIcon()
	{
		#if windows
		WindowsData.removeWindowIcon();
		#end
	}

	public static function reset()
	{
		#if windows
		Transparency.reset();
		#end
	}
	public static function allowHighDPI()
	{
		#if windows
		WindowsData.registerHighDpi();
		#end
	}
}
