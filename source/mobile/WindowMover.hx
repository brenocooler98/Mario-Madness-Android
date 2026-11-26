package mobile;

#if android
import lime.system.JNI;
#end

class WindowMover
{
	#if android
	static var setWindowJNI:Dynamic = null;
	static var setControlsJNI:Dynamic = null;
	static var addImageJNI:Dynamic = null;
	static var clearImagesJNI:Dynamic = null;
	#end

	public static function setWindow(active:Bool, left:Int, top:Int, right:Int, bottom:Int, offsetX:Float, offsetY:Float):Void
	{
		#if android
		try
		{
			if (setWindowJNI == null)
				setWindowJNI = JNI.createStaticMethod('mariomadness/WindowMover', 'setWindow', '(ZIIIIFF)V');
			if (setWindowJNI != null)
				setWindowJNI(active, left, top, right, bottom, offsetX, offsetY);
		}
		catch (e:Dynamic) {}
		#end
	}

	public static function setControls(ops:String):Void
	{
		#if android
		try
		{
			if (setControlsJNI == null)
				setControlsJNI = JNI.createStaticMethod('mariomadness/WindowMover', 'setControls', '(Ljava/lang/String;)V');
			if (setControlsJNI != null)
				setControlsJNI(ops);
		}
		catch (e:Dynamic) {}
		#end
	}

	public static function addImage(key:String, data:String):Void
	{
		#if android
		try
		{
			if (addImageJNI == null)
				addImageJNI = JNI.createStaticMethod('mariomadness/WindowMover', 'addImage', '(Ljava/lang/String;Ljava/lang/String;)V');
			if (addImageJNI != null)
				addImageJNI(key, data);
		}
		catch (e:Dynamic) {}
		#end
	}

	public static function clearImages():Void
	{
		#if android
		try
		{
			if (clearImagesJNI == null)
				clearImagesJNI = JNI.createStaticMethod('mariomadness/WindowMover', 'clearImages', '()V');
			if (clearImagesJNI != null)
				clearImagesJNI();
		}
		catch (e:Dynamic) {}
		#end
	}
}
