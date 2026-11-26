package video;

#if VIDEOS_ALLOWED
import hxvlc.flixel.FlxVideoSprite;

class VideoSprite extends FlxVideoSprite
{
	public var readyCallback:Void->Void;
	public var finishCallback:Void->Void;

	var pendingFinish:Bool = false;

	public function new(x:Float = 0, y:Float = 0)
	{
		#if android
		mobile.SessionLog.mark('video player');
		#end
		super(null, x, y);
		bitmap.onVideoFormatSetup.add(onReady);
		bitmap.onEndReached.add(onFinish);
		bitmap.onEncounteredError.add(function(_:String) pendingFinish = true);
	}

	public function playVideo(path:String, loop:Bool = false):Void
	{
		if (!alive)
			revive();

		#if android
		mobile.SessionLog.mark('video ' + path);
		#end

		if (load(path, loop ? [':input-repeat=65535'] : null))
		{
			if (!play())
				pendingFinish = true;
		}
		else
			pendingFinish = true;
	}

	function onReady():Void
	{
		if (readyCallback != null)
			readyCallback();
	}

	function onFinish():Void
	{
		pendingFinish = false;
		if (finishCallback != null)
			finishCallback();
		if (exists)
			kill();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (pendingFinish)
			onFinish();
	}
}
#else
class VideoSprite extends flixel.FlxSprite
{
	public var readyCallback:Void->Void;
	public var finishCallback:Void->Void;
	public var bitmap:Dynamic = {pause: function() {}, resume: function() {}, stop: function() {}};

	public function playVideo(path:String, loop:Bool = false):Void
	{
		if (finishCallback != null)
			finishCallback();
	}
}
#end
