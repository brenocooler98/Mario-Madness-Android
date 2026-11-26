package mobile;

#if android
import lime.system.JNI;
#end

class WindowMover
{
	#if android
	static var setOffsetJNI:Dynamic = null;
	#end

	public static function setOffset(x:Float, y:Float):Void
	{
		#if android
		try
		{
			if (setOffsetJNI == null)
				setOffsetJNI = JNI.createStaticMethod('mariomadness/WindowMover', 'setOffset', '(FF)V');
			if (setOffsetJNI != null)
				setOffsetJNI(x, y);
		}
		catch (e:Dynamic) {}
		#end
	}
}
