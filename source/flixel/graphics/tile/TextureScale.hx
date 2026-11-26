package flixel.graphics.tile;

import flixel.graphics.FlxGraphic;

class TextureScale
{
	static var scales:Map<FlxGraphic, Float> = new Map<FlxGraphic, Float>();
	static var count:Int = 0;

	public static inline function get(graphic:FlxGraphic):Float
	{
		if (count == 0 || graphic == null)
			return 1;
		var scale:Null<Float> = scales.get(graphic);
		return scale == null ? 1 : scale;
	}

	@:access(flixel.graphics.FlxGraphic)
	public static function apply(graphic:FlxGraphic, originalWidth:Int, originalHeight:Int):Void
	{
		if (graphic == null || graphic.bitmap == null || originalWidth <= 0 || graphic.bitmap.width >= originalWidth)
			return;

		var scale:Float = graphic.bitmap.width / originalWidth;
		if (!scales.exists(graphic))
			count++;
		scales.set(graphic, scale);
		graphic.width = originalWidth;
		graphic.height = originalHeight;
	}

	public static function remove(graphic:FlxGraphic):Void
	{
		if (graphic != null && scales.remove(graphic))
			count--;
	}
}
