package mobile;

class BuildMacro
{
	public static macro function timestamp():haxe.macro.Expr
	{
		return macro $v{Std.string(Date.now().getTime())};
	}
}
