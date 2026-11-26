package;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxState;
#if VIDEOS_ALLOWED
import hxvlc.flixel.FlxVideoSprite;
#end

class DSVideo extends FlxBasic
{
	public var finishCallback:Void->Void;

	public var finished:Bool = false;

	public var state:FlxState;

	#if VIDEOS_ALLOWED
	public var sprite:FlxVideoSprite;

	var failed:Bool = false;
	#end

	public function new(name:String, camera:FlxCamera, state:FlxState)
	{
		super();

		this.state = state;

		finishCallback = function()
		{
			finished = true;
		};

		#if VIDEOS_ALLOWED
		sprite = new FlxVideoSprite(null, 448, 72);
		sprite.cameras = [camera];
		sprite.bitmap.onVideoFormatSetup.add(function()
		{
			sprite.setGraphicSize(384, 576);
			sprite.updateHitbox();
			sprite.setPosition(448, 72);
		});
		sprite.bitmap.onEndReached.add(onComplete);
		sprite.bitmap.onEncounteredError.add(function(_:String) failed = true);
		state.add(sprite);

		if (!sprite.load(name) || !sprite.play())
			failed = true;
		#else
		finished = true;
		#end
	}

	#if VIDEOS_ALLOWED
	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (failed)
		{
			failed = false;
			onComplete();
		}
	}

	function onComplete():Void
	{
		if (sprite != null)
		{
			sprite.visible = false;
			state.remove(sprite);
		}

		if (finishCallback != null)
			finishCallback();
	}

	override function destroy():Void
	{
		if (sprite != null)
		{
			state.remove(sprite);
			sprite.destroy();
			sprite = null;
		}
		super.destroy();
	}
	#end
}
