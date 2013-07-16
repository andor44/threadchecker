package me.neferty.projects.tc;

import haxe.crypto.BaseCode;
import haxe.crypto.Md5;
import haxe.io.Path;
import neko.Lib;
import haxe.Http;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

using Lambda;

/**
 * Copyright (c) 2013 Andor Uhlar
 * This software is provided 'as-is', without any express or implied warranty. In no event will the authors be held liable for any damages arising from the use of this software.
 * Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
 * 
 *    1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
 * 
 *    2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
 *
 *    3. This notice may not be removed or altered from any source distribution.
 *
 * @author Andor
 */

class Config
{
	public var board_name : String;
	public var thread_id : Int;
	public var overwrite_protection : Bool;
	public var loop : Bool;
	public var loop_freq : Int;
	public var recursive_md5_scan : Bool;
	public var scanpath : String;
	public var savepath : String;
	public var use_uploader_filename : Bool;
	
	public function new(){}
}

class Main 
{
	static var bc = new BaseCode(haxe.io.Bytes.ofString("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"));
	
	// expects full path with trailing slash
	static function calc_md5s(path : String, recursive : Bool, extensions : Array<String>) : List<String>
	{
		var flist = FileSystem.readDirectory(path);
		
		var images = flist.filter(function(fname:String) : Bool {
			return !FileSystem.isDirectory(path + fname) && extensions.has(Path.extension(fname).toLowerCase()); 
		});
		
		var local_md5s = new List<String>();
		
		for (i in images)
		{
			local_md5s.add(bc.encodeBytes(Md5.make(File.getBytes(path + i))).toString());
			Lib.println(path + i + " - " + local_md5s.last());
		}
		
		if (recursive)
		{
			for (i in flist)
			{
				if (FileSystem.isDirectory(path + i))
				{
					local_md5s = local_md5s.concat(calc_md5s(Path.addTrailingSlash(path + i), true, extensions));
				}
			}
		}
		
		return local_md5s;
	}
	
	static function save_thread(local_md5s : List<String>) : List<String>
	{
		Lib.println("Fetching posts");
		var thread : Dynamic = null;
		try 
		{
			thread = Json.parse(Http.requestUrl("http://api.4chan.org/" + conf.board_name + "/res/" + conf.thread_id + ".json"));
		}
		catch (e : Dynamic)
		{
			Lib.println("Unable to fetch thread from 4chan, exiting");
			Sys.exit(1);
		}
		
		var new_md5s = new List<String>();
		var posts : Iterable<Dynamic> = thread.posts;
		
		for (i in posts)
		{
			if (i.md5 != null && !local_md5s.has(i.md5.substr(0,22)))
			{
				Lib.println("Missing image: " + i.filename + i.ext + ", downloading...");
				File.saveContent(conf.savepath + (conf.use_uploader_filename ? i.filename : i.tim) + i.ext, Http.requestUrl("http://images.4chan.org/" + conf.board_name + "/src/" + i.tim + i.ext));
				new_md5s.add(i.md5.substr(0,22));
			}
			else if (i.md5 != null && local_md5s.has(i.md5.substr(0,22)))
				Lib.println("Already have image: " + i.filename + i.ext);
		}
		return new_md5s;
	}
	
	static var conf : Config = new Config();
	
	static function main() 
	{
		var interactive_mode = false;
		if (Sys.args().length > 0)
		{
			try
			{
				conf = cast Json.parse(File.getContent(Sys.args()[0]));
			}
			catch (e : Dynamic)
			{
				Lib.println("Failed to read given config file, it's probably invalid.");
				Sys.exit(1);
			}
			Lib.println("Using '" + Sys.args()[0] + "' as config file");
		}
		else if (FileSystem.exists("threadchecker.json"))
		{
			try
			{
				conf = cast Json.parse(File.getContent("threadchecker.json"));
			}
			catch (e : Dynamic)
			{
				Lib.println("Failed to read threadchecker.json, it's probably invalid.");
				Sys.exit(1);
			}
			Lib.println("Using threadchecker.json as config file");
		}
		else 
			interactive_mode = true;
		
		if (interactive_mode)
		{
			Lib.println("Interactive mode (on true/false questions, y means true, anything else false): ");
			do {
				Lib.print("Give me a path to scan: "); conf.scanpath = Sys.stdin().readLine();
			} while (!FileSystem.exists(conf.scanpath) || !FileSystem.isDirectory(conf.scanpath));
			
			Lib.print("Perform a recursive scan? "); 
			conf.recursive_md5_scan = Sys.stdin().readLine().toLowerCase() == 'y';
			
			Lib.print("Should I save in the same directory as the scan? ");
			if (Sys.stdin().readLine().toLowerCase() == 'y')
				conf.savepath = conf.scanpath;
			else
			{
				do {
					Lib.print("Give me a path to save to: "); conf.savepath = Sys.stdin().readLine();
				} while (!FileSystem.exists(conf.savepath) || !FileSystem.isDirectory(conf.savepath));
			}
			
			Lib.print("Board name: "); conf.board_name = Sys.stdin().readLine();
			
			do {
				Lib.print("Thread id: "); conf.thread_id = Std.parseInt(Sys.stdin().readLine());
			} while (conf.thread_id == null || conf.thread_id == 0);
			
			Lib.print("Use uploader's filename? "); conf.use_uploader_filename = Sys.stdin().readLine().toLowerCase() == 'y';
			
			Lib.print("Loop? "); conf.loop = Sys.stdin().readLine().toLowerCase() == 'y';
			
			do {
				Lib.print("Loop interval (in seconds): "); conf.loop_freq = Std.parseInt(Sys.stdin().readLine());
			} while (conf.loop_freq == null || conf.loop_freq == 0);
			
			Lib.println("Writing given config into '" + conf.board_name + "-" + conf.thread_id + ".json' then running it");
			File.saveContent(conf.board_name + "-" + conf.thread_id + ".json", Json.stringify(conf));
		}
		
		conf.savepath = Path.addTrailingSlash(conf.savepath);
		
		Lib.println("Calculating MD5s of images in '" + FileSystem.fullPath(conf.savepath) + "'...");
		var local_md5s = calc_md5s(FileSystem.fullPath(conf.savepath), conf.recursive_md5_scan, ["jpg", "gif", "png"]);
		
		if (conf.loop)
		{
			Lib.println("Looping is on. Press Ctrl+C to exit or just close this window");
			while (true)
			{
				local_md5s = local_md5s.concat(save_thread(local_md5s));
				Lib.println("Waiting " + conf.loop_freq + " seconds...");
				Sys.sleep(conf.loop_freq);
			}
		}
		else
		{
			Lib.println("Saving then exiting");
			save_thread(local_md5s);
		}
		
		Lib.println("Exiting");
	}
}