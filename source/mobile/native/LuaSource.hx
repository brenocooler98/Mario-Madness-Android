package mobile.native;

#if android
@:keep
@:build(mobile.native.NativeBuild.addFiles('project/lua51/src', 'c', 'mario_lua51'))
#end
class LuaSource
{
	public static function init():Void {}
}
