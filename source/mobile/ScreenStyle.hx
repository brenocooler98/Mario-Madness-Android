package mobile;

#if android
import lime.system.JNI;
#end

class ScreenStyle
{
	#if android
	static var applyJNI:Dynamic = null;
	#end

	public static function apply(full:Bool):Void
	{
		#if android
		try
		{
			if (applyJNI == null)
				applyJNI = JNI.createStaticMethod('mariomadness/ScreenStyle', 'apply', '(Z)V');
			if (applyJNI != null)
				applyJNI(full);
		}
		catch (e:Dynamic) {}
		#end
	}
}
