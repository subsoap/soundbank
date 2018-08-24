local M = {}

M.verbose = false

M.default_gain = 1.0
M.default_delay = 0.0
M.default_gated = true
M.gated_time = 0.2 -- time in seconds between the same sound can play

M.music_playlists = {}
M.disable_music_if_device_music_is_playing = true
M.last_music_played = nil

M.FADING_NO_FADING = 0
M.FADING_FADE_OUT = 1
M.FADING_FADE_IN = 2
M.fading = M.NO_FADING
M.fading_timer = 0
M.fading_time = 6

M.PLAYBACK_NORMAL = 0
M.PLAYBACK_SHUFFLE = 1


M.music_play_next = nil

M.music_queue = {}

M.sound_queue = {}
M.soundbank_loading_queue = {}

M.soundbanks = {}
M.SOUNDBANK_UNLOADED = 0
M.SOUNDBANK_LOADING = 1
M.SOUNDBANK_LOADED = 2

M.audio_tags = 
{
	master = 0.8,
	sounds = 1.0,
	music = 1.0,
	ambience = 1.0,
	voice = 1.0,
}

M.sounds = {}
M.gated = {}

M.playlists = {}
M.PLAYLIST_NOT_PLAYING = 0
M.PLAYLIST_WAITING_FOR_SOUNDBANK = 1
M.PLAYLIST_PLAYING = 2



---- SoundBanks ----

function M.add_soundbank(name, url, list)
end

-- this has to be done within the context of the update() of the soundbank.script
function M.load_soundbank(name)
	if not M.soundbanks[name] then
		-- assume music soundbank for now
		M.soundbanks[name] = {}
		M.soundbanks[name].status = M.SOUNDBANK_UNLOADED
		M.soundbanks[name].url = "#" .. name
	end
	if M.soundbanks[name] then
		if not (M.soundbanks[name].status == M.SOUNDBANK_LOADED) and not (M.soundbanks[name].status == M.SOUNDBANK_LOADING) then
			M.soundbanks[name].status = M.SOUNDBANK_LOADING
			table.insert(M.soundbank_loading_queue, name)
		end
	end
end

function M.process_soundbank_loading_queue()
	for _, value in pairs(M.soundbank_loading_queue) do
		M.soundbanks[value].status = M.SOUNDBANK_LOADING
		msg.post(M.soundbanks[value].url, "async_load")
		
	end
	M.soundbank_loading_queue = {}
end

function M.report_loaded_soundbank(url)
	
	local name = nil -- lookup name based on url.fragment
	for key, value in pairs(M.soundbanks) do
		if hash(key) == url.fragment then
			name = key
		end
	end

	
	msg.post(url, "enable")
	if not M.soundbanks[name] then
		M.soundbanks[name] = {}
		M.soundbanks[name].url = url
	end
	M.soundbanks[name].status = M.SOUNDBANK_LOADED

	if M.verbose then print("SoundBank: soundbank loaded " .. url.fragment) end
end

function M.unload_soundbank(name)
	pprint(M.soundbanks[name])
	M.soundbanks[name].status = M.SOUNDBANK_UNLOADED
	msg.post(M.soundbanks[name].url, "disable")
	msg.post(M.soundbanks[name].url, "unload") -- final is called auto here
	if M.verbose then print("SoundBank: soundbank unloaded " .. name) end
end

---- Tags ----

function M.update_tag(tag, gain)
	M.audio_tags[tag] = gain
end

function M.add_tag(tag, gain)
	M.update_tag(tag, gain)
end

---- Music ----

function M.get_time_left_current_playing_music(playlist)
end

function M.add_playlist(playlist, songs, playback)
	if not M.playlists[playlist] then
		M.playlists[playlist] = {}
	else
		assert(not M.playlists[playlist], "SoundBank: add_playlist - playlist already exists " .. playlist)
	end
	local total = 0
	M.playlists[playlist].tracks = {}
	
	for track, _ in pairs(songs) do -- this block is kind of confusing, better names?
		total = total + 1
		M.playlists[playlist].tracks[total] = {}
		M.playlists[playlist].tracks[total].name = track
		M.playlists[playlist].tracks[total].url = songs[track].url or "#" .. track
		M.playlists[playlist].tracks[total].time = songs[track].time
	end
	if playback and playback == M.PLAYBACK_SHUFFLE then
		M.playlists[playlist].playback = M.PLAYBACK_SHUFFLE
		M.playlists[playlist].shuffle_list = {}
		for i=1, total, 1 do
			M.playlists[playlist].shuffle_list[i] = i
		end
		M.playlists[playlist].shuffle_list = M.shuffle(M.playlists[playlist].shuffle_list)
	end
	if M.verbose then print("SoundBank: playlist added " .. playlist) end
end

function M.shuffle(tbl)
	size = #tbl
	for i = size, 1, -1 do
		local rand = math.random(size)
		tbl[i], tbl[rand] = tbl[rand], tbl[i]
	end
	return tbl
end

function M.shuffle_copy(tbl)
	local tbl_out = {}
	size = #tbl
	for i = size, 1, -1 do
		local rand = math.random(size)
		tbl_out[i], tbl_out[rand] = tbl[rand], tbl[i]
	end
	return tbl_out
end

function M.process_fading(dt)
	M.fade_in_music(dt)
	M.fade_out_music(dt)
end

function M.fade_in_music(dt)
	if M.fading == M.FADING_FADE_IN then
		M.fading_timer = M.fading_timer + dt
		if M.fading_timer < M.fading_time then
			M.fading_timer = math.min(M.fading_timer + dt, M.fading_time)
			sound.set_group_gain("music", M.fading_timer / M.fading_time)
		else
			M.fading = M.FADING_NO_FADING
			sound.set_group_gain("music", 1.0)
			M.fading_timer = 0
			if M.verbose then print("SoundBank: faded in") end
		end
	end
end

function M.fade_out_music(dt)
	if M.fading == M.FADING_FADE_OUT then
		M.fading_timer = M.fading_timer + dt
		if M.fading_timer < M.fading_time then
			M.fading_timer = math.min(M.fading_timer + dt, M.fading_time)
			sound.set_group_gain("music", 1.0 - M.fading_timer / M.fading_time)
		else
			M.fading = M.FADING_NO_FADING
			sound.set_group_gain("music", 0.0)
			M.fading_timer = 0
			if M.verbose then print("SoundBank: faded out") end
		end
	end	
end

-- this is playing music that is not on a playlist
-- song length can be longer than the audio file, you can set component to loop
-- fades is a table {fade_in = bool, fade_out = bool} which fades in at start of play and fades out at end (useful for loops)
function M.play_music(song, song_length, url, fades) -- add to a queue, wait until loaded, then play
	if M.disable_music_if_device_music_is_playing == true and sound.is_music_playing() then return false end
	
end

function M.process_music_queue()
	-- wait for the soundbank for the music to be loaded
	-- update the progress of the currently playing song
end

function M.process_playlists(dt) -- need to break this into more functions probably
	for key, value in pairs(M.playlists) do
		if M.playlists[key].status == M.PLAYLIST_PLAYING then
			if not M.playlists[key].current_time then M.playlists[key].current_time = 0 end
			M.playlists[key].current_time = M.playlists[key].current_time + dt
			if M.playlists[key].current_time > M.playlists[key].tracks[M.playlists[key].current_track].time then
				-- current song is over
				-- stop current song by its actual url - this has to be done because of looping songs
				-- TODO add fadeout support based on total time x fade time near the end
				msg.post(M.soundbanks[M.playlists[key].current_song].url_actual, "stop_sound")
				M.unload_soundbank(M.playlists[key].current_song)
				-- load next song
				M.playlists[key].status = M.PLAYLIST_WAITING_FOR_SOUNDBANK
				if M.playlists[key].playback ~= M.PLAYBACK_SHUFFLE then
					M.playlists[key].current_track = math.fmod(M.playlists[key].current_track + 1, #M.playlists[key].tracks + 1)
					if M.playlists[key].current_track == 0 then M.playlists[key].current_track = 1 end -- should reshuffle here and make sure next song is not last song
				else
					M.playlists[key].current_shuffle_list = math.fmod(M.playlists[key].current_shuffle_list + 1, #M.playlists[key].shuffle_list + 1)
					if M.playlists[key].current_shuffle_list == 0 then M.playlists[key].current_shuffle_list = 1 end
					M.playlists[key].current_track = M.playlists[key].shuffle_list[M.playlists[key].current_shuffle_list]
				end
				M.playlists[key].current_time = 0
			end
		end		
		if M.playlists[key].status == M.PLAYLIST_WAITING_FOR_SOUNDBANK then
			
			local current_song = nil

			-- something is fucked up here!
			if M.playlists[key].playback == M.PLAYBACK_SHUFFLE then
				current_song = M.playlists[key].tracks[M.playlists[key].shuffle_list[M.playlists[key].current_shuffle_list]].name
			else
				current_song = M.playlists[key].tracks[M.playlists[key].current_track].name
			end

			print(current_song)

			M.playlists[key].current_song = current_song

			M.load_soundbank(current_song)

			if M.soundbanks[current_song] and M.soundbanks[current_song].status == M.SOUNDBANK_LOADED then
				-- construct url to the actual audio component for the music
				M.soundbanks[current_song].url_actual = msg.url()
				M.soundbanks[current_song].url_actual.socket = current_song
				M.soundbanks[current_song].url_actual.path = "/music"
				M.soundbanks[current_song].url_actual.fragment = "music"
				
				M.playlists[key].status = M.PLAYLIST_PLAYING
				msg.post(M.soundbanks[current_song].url_actual, "play_sound")
			end
			
		end
	end
end

function M.play_playlist(playlist)
	if not M.playlists[playlist] then print("SoundBank: play_playlist - playlist not found " .. playlist) return false end
	if M.disable_music_if_device_music_is_playing == true and sound.is_music_playing() then return false end

	--M.PLAYLIST_NOT_PLAYING
	--M.PLAYLIST_WAITING_FOR_SOUNDBANK
	--M.PLAYLIST_PLAYING
	
	M.playlists[playlist].status = M.PLAYLIST_WAITING_FOR_SOUNDBANK
	if M.playlists[playlist].playback ~= M.PLAYBACK_SHUFFLE then
		M.playlists[playlist].current_track = 1
	else
		M.playlists[playlist].current_shuffle_list = 1
		M.playlists[playlist].current_track = M.playlists[playlist].shuffle_list[1]
	end
end

function M.stop_playlist(playlist)
end

function M.stop_all_music()
end

---- Sounds ----

function M.play_sound(sound, gain, delay, gated, tag, url)
	assert(sound, "SoundBank: play_sound - You must specify a sound to play.")
	if M.verbose then print("SoundBank: play_sound - " .. sound) end

	gain = gain or M.default_gain
	delay = delay or M.default_delay
	if gated == nil then
		gated = gated or M.default_gated
	end
	
	local tag_gain
	if tag_gain and M.audio_tags[tag] then -- if a tag is listed then use it
		tag_gain = M.audio_tags[tag].gain
	elseif M.sounds[sound] then -- check if the sound name has a tag set for it
		if M.sounds[sound].tag then
			tag_gain = M.audio_tags[M.sounds[sound].tag].gain
		end
	else -- else use the default gain which should be 1.0 no change
		tag_gain = M.default_gain
	end

	gain = gain * tag_gain * M.audio_tags["master"]

	if url then
		-- check if it's actually a url?
	elseif M.sounds[sound] then
		if M.sounds[sound].url then
			url = M.sounds[sound].url
		end
	else
		url = "#" .. sound
	end

	if gated then
		if M.gated[sound] == nil then
			M.gated[sound] = {}
			M.gated[sound].timer = M.gated_time
		else
			if M.verbose then print("SoundBank: play_sound - " .. sound .. " was skipped as gated") end
			return false
		end
	end

	M.add_sound_to_queue(url, delay, gain)
end

function M.stop_sound(sound, url)
	msg.post("#sound", "stop_sound")
end

function M.add_sound(sound, url, delay, gain)
end

function M.add_sound_to_queue(url, delay, gain)
	table.insert(M.sound_queue, {url = url, delay = delay, gain = gain})
end

function M.process_sound_queue()
	if next(M.sound_queue) ~= nil then
		for key, _ in pairs(M.sound_queue) do
			local sound = M.sound_queue[key]
			msg.post(sound.url, "play_sound", {delay = sound.delay, gain = sound.gain})
		end
		M.sound_queue = {}
	end
end

---- General ----

function M.update(dt)
	for key, _ in pairs(M.gated) do
		M.gated[key].timer = M.gated[key].timer - dt
		if M.gated[key].timer <= 0 then
			M.gated[key] = nil
		end
	end
	M.process_sound_queue()
	M.process_music_queue()
	M.process_playlists(dt)
	M.process_fading(dt)
	M.process_soundbank_loading_queue()
	if M.disable_music_if_device_music_is_playing == true and sound.is_music_playing() then M.stop_all_music() end
end


return M