package;

import flixel.FlxBasic;
import flixel.FlxG;
#if VIDEOS_ALLOWED
import hxvlc.flixel.FlxVideo as VlcVideo;
#end

class FlxVideo extends FlxBasic
{
	public var finishCallback:Void->Void = null;

	#if VIDEOS_ALLOWED
	public static var video:VlcVideo;

	var done:Bool = false;
	#end

	public function new(name:String)
	{
		super();

		#if VIDEOS_ALLOWED
		if (video != null)
			destroyVideo();

		video = new VlcVideo();
		video.onEndReached.add(onComplete);
		video.onEncounteredError.add(function(_:String) onComplete());
		FlxG.addChildBelowMouse(video);

		if (!video.load(name) || !video.play())
			FlxG.signals.postUpdate.addOnce(onComplete);
		#else
		FlxG.signals.postUpdate.addOnce(function()
		{
			if (finishCallback != null)
				finishCallback();
		});
		#end
	}

	#if VIDEOS_ALLOWED
	static function destroyVideo():Void
	{
		if (video == null)
			return;
		FlxG.removeChild(video);
		video.dispose();
		video = null;
	}

	function onComplete():Void
	{
		if (done)
			return;
		done = true;

		FlxG.signals.postUpdate.addOnce(function()
		{
			destroyVideo();
			if (finishCallback != null)
				finishCallback();
		});
	}
	#end
}
