string forum_username = "CGBot";
string forum_password = "Notontherepo";

string forum = "http://www.crimbogrotto.com";

// Records
record mes
{
	string sender;
	string message;
	string channel;
	string timestamp;
};

record kmessage {
   int id;                   // message id
   string type;              // possible values observed thus far: normal, giftshop
   int fromid;               // sender's playerid (0 for npc's)
   int azunixtime;           // KoL server's unix timestamp
   string message;           // message (not including items/meat)
   int[item] items;          // items included in the message
   int meat;                 // meat included in the message
   string fromname;          // sender's playername
   string localtime;         // your local time according to your KoL account, human-readable string
};

record member
{
	string name;
	int id;
	string title;
	int rank;
};

record log_entry{
	string time;
	string user;
	item it;
	int num;
	string action;
};

record stash_entry{
	int num;
	int last_id_parsed;
};

record thread
{
	string title;
	int last_post;
	string last_poster;
	int num_posts;
};

record trigger
{
	string trig;
	string response;
};

string html_unencode( string text )
{
	text = text.replace_string( "&quot;" , "\"" ).replace_string( "&gt;" , ">" ).replace_string( "&lt;" , "<" ).replace_string( "&amp;" , "&" );
	matcher m_links = create_matcher( "</?a[^>]*>" , text );
	text = replace_all( m_links , "" );
	return text;
}

// Kmail functions
kmessage[int] mail;

// loads all of your inbox (up to 100) into the global "mail"
void load_kmail()
{ 
	mail.clear();
	matcher k = create_matcher( "'id' =\\> '(\\d+)',\\s+'type' =\\> '(.+?)',\\s+'fromid' =\\> '(-?\\d+)',\\s+'azunixtime' =\\> '(\\d+)',\\s+'message' =\\> '(.+?)',\\s+'fromname' =\\> '(.+?)',\\s+'localtime' =\\> '(.+?)'"
	, visit_url( "api.php?pwd&what=kmail&format=php&count=100&for=" + url_encode( "CGBot" ) ) );
	int n;
	while ( k.find() )
	{
		n = count( mail );
		mail[n].id = to_int( k.group(1) );
		mail[n].type = k.group(2);
		mail[n].fromid = to_int( k.group(3) );
		mail[n].azunixtime = to_int( k.group(4) );
		matcher mbits = create_matcher( "(.*?)\\<center\\>(.+?)$" , k.group(5).replace_string( "\\'","'" ) );
		if ( mbits.find() )
		{
			mail[n].meat = extract_meat( mbits.group(2) );
			mail[n].items = extract_items( mbits.group(2) );
			mail[n].message = mbits.group( to_int( mail[n].meat > 0 || count( mail[n].items ) > 0 ) );
		}
		else mail[n].message = k.group(5);
		mail[n].fromname = k.group(6);
		mail[n].localtime = k.group(7);
	}
}

void kmail(string to, buffer message)
{
	string fixed;
 	fixed = message.html_unencode();
	fixed = url_encode( fixed );
	string url = visit_url( "sendmessage.php?pwd=&action=send&towho="+to+"&message="+fixed , true , true );
	if ( !contains_text( url , "Message sent." ) ) print( "The message to " + to + " didn't send for some reason." );
}

boolean send_gift( string to , string message , int[item] goodies , int meat , string insidenote )
{
	// parse items into query string
	string itemstring;
	int j = 0;
	int[item] extra;
	foreach i in goodies
	{
		if( is_tradeable( i ) || is_giftable( i ) )
		{
			j += 1;
			if ( j < 4 )
			itemstring = itemstring + "&howmany"+j+"="+goodies[i]+"&whichitem"+j+"="+to_int(i);
			else extra[i] = goodies[i];
		}
	}
	int shipping = 200;
	int pnum = 3;
	if ( count( goodies ) < 3 )
	{
		shipping = 50 * max( 1 , count( goodies ) );
		pnum = max( 1 , count( goodies ) );
	}
	// send gift
	string url = visit_url( "town_sendgift.php?pwd=&towho=" + to + "&note=" + message.html_unencode().url_encode() + "&insidenote=" + insidenote.html_unencode().url_encode() + "&whichpackage=" + pnum + "&fromwhere=0&sendmeat=" + meat + "&action=Yep." + itemstring , true , true );
	if ( count( extra ) > 0 ) return send_gift( to , message , extra , 0 , insidenote );
	return true;
}

boolean kmail(string to, string message, int[item] goodies, int meat)
{
	string itemstring;
	int j = 0;
	string[int] itemstrings;
	foreach i in goodies
	{
		if ( is_tradeable( i ) || is_giftable( i ) )
		{
			j += 1;
			itemstring = itemstring + "&howmany" + j + "=" + goodies[i] + "&whichitem" + j + "=" + to_int(i);
			if ( j > 10 )
			{
				itemstrings[count( itemstrings )] = itemstring;
				itemstring = '';
				j = 0;
			}
		}
	}
	if ( itemstring != "" ) itemstrings[count( itemstrings )] = itemstring;
	if ( count(itemstrings) == 0 ) itemstrings[0] = "";
	foreach q in itemstrings
	{
		string url = visit_url( "sendmessage.php?pwd=&action=send&towho=" + to + "&message=" + message.html_unencode().url_encode() + "&savecopy=on&sendmeat=" + meat + itemstrings[q] , true , true );
		if( contains_text( url , "That player cannot receive Meat or items" ) )
		return send_gift( to , message , goodies , meat , "" );
	}
	return true;
}
boolean kmail( string to , string message , int meat )
{
	int[item] nothing; return kmail( to , message , nothing , meat );
}
boolean kmail( string to , string message , int[item] goodies )
{
	return kmail( to , message , goodies , 0 );
}

// End Kmail functions

// Clan administration functions
string cached_roster;
string cached_whitelist;

void update_rosters()
{
	cached_roster = visit_url( "clan_detailedroster.php" ).to_lower_case();
	cached_whitelist = visit_url( "clan_whitelist.php" ).to_lower_case();
}

boolean in_clan( string name , string page )
{
	matcher m_det = create_matcher( "<a[^>]+><b>" + name.to_lower_case() + "</b>" , page );
	if( m_det.find() ) return true;
	return false;
}

boolean in_clan( string name , boolean cache )
{
	if( cache )
	{
		if( cached_roster != "" )
		{
			return in_clan( name , cached_roster );
		}
	}
	cached_roster = visit_url( "clan_detailedroster.php" ).to_lower_case();
	return in_clan( name , cached_roster );
}

boolean in_clan( string name )
{
	return in_clan( name , true );
}

boolean on_whitelist( string name , string page )
{
	matcher m_wl = create_matcher( "<a[^>]+><b>" + name.to_lower_case() + "</b>" , page );
	if( m_wl.find() ) return true;
	return false;
}

boolean on_whitelist( string name , boolean cache )
{
	if( cache )
	{
		if( cached_whitelist != "" )
		{
			return in_clan( name , cached_whitelist );
		}
	}
	cached_whitelist = visit_url( "clan_whitelist.php" ).to_lower_case();
	return in_clan( name , cached_whitelist );
}

boolean on_whitelist( string name )
{
	return in_clan( name , true );
}

int[string] ranks;
void get_ranks()
{
	string page = visit_url( "clan_whitelist.php" );
	page = page.substring( page.index_of( "<b>Add a player to your Clan Whitelist</b>" ) );
	matcher m_ranks = create_matcher( "<option value=(\\d+)>([^(]+) " , page );
	while( m_ranks.find() )
	{
		ranks[m_ranks.group(2).to_lower_case()]=m_ranks.group(1).to_int();
	}
}
// End Clan Administration functions

// Forum functions
string sid;

boolean login()
{
	string page = visit_url( forum + "/ucp.php?mode=login&username=" + forum_username + "&password=" + forum_password + "&redirect=./ucp.php?mode=login&redirect=index.php&login=Login");
	matcher m_getsid = create_matcher( "\\?sid=([^\"]+)\"" , page );
	if( m_getsid.find() )
	{
		sid = m_getsid.group(1);
		return true;
	}
	return false;
}

int[string]forums;
void get_forums()
{
	string page = visit_url( forum + "/index.php?sid=" + sid );
	matcher m_forum = create_matcher( "<a.+?\\?f=(\\d+)[^>]+>([^<]+)</a>" , page );
	while( m_forum.find() )
	{
		forums[m_forum.group(2)] = m_forum.group(1).to_int();
	}
}

thread[int] get_threads( int forum_num )
{
	thread[int] all_threads;
	
	string page = visit_url( forum + "/viewforum.php?f=" + forum_num + "&sid=" + sid );
	matcher m_startthread = create_matcher( "<li class=\"row bg" , page );
	while( m_startthread.find() )
	{
		string thread_section = page.substring( m_startthread.start() , page.index_of( "</li>" , m_startthread.start() ) ); // this line threw an error.
		matcher m_thread = create_matcher( "\\./viewtopic\\.php\\?f=\\d+&amp;t=(\\d+)&amp;sid="+sid+"\" class=\"topictitle\">(.+?)</a>" , thread_section );
		matcher m_lastposter = create_matcher( "Last post </dfn>by <a[^>]+>(.+?)</a>" , thread_section );
		matcher m_numposts = create_matcher( "<dd class=\"posts\">(\\d+) <dfn>" , thread_section );
		matcher m_lastpage = create_matcher( "\"\./viewtopic.php\\?f=\\d+&amp;t=\\d+&amp;p=(\\d+)[^\"]+\"><img.+?title=\"View the latest post\" /></a>" , thread_section );
		int tid;
		if( m_thread.find() )
		{
			tid = m_thread.group(1).to_int();
			all_threads[tid].title = m_thread.group(2);
		}
		if( m_lastposter.find() )
		{
			all_threads[tid].last_poster = m_lastposter.group(1);
		}
		if( m_numposts.find() )
		{
			all_threads[tid].num_posts = m_numposts.group(1).to_int() + 1;
		}
		if( m_lastpage.find() )
		{
			all_threads[tid].last_post = m_lastpage.group(1).to_int();
		}
	}
	
	return all_threads;
}
// End Forum functions

string[int] admins;
file_to_map( "admins.txt" , admins );

boolean is_admin( string name )
{
	foreach key in admins
	{
		if( name.to_lower_case() == admins[key].to_lower_case() ) return true;
	}
	return false;
}

boolean is_demi( string name )
{
	if( cached_whitelist == "" )
	{
		cached_whitelist = visit_url( "clan_whitelist.php" ).to_lower_case();
	}
	matcher m_demi = create_matcher( "(?:<tr><td><input.+?<b>" + name.to_lower_case() + "</b> \\(#\\d+\\)</a></td><td>peppermint mocha</td>.+?</tr>|<tr><td><input.+?<b>" + name.to_lower_case() + "</b> \\(#\\d+\\)</a></td><td><select name=level\\d+>.*?<option value=3 selected>peppermint mocha \\(&deg;93\\)</option>.*?</select>.+?</tr>)" , cached_whitelist );
	return m_demi.find();
}

// Uncomment this if you aren't running a modified build of mafia
/*
void chat_public( string chan , string mes )
{
	if( chan == "clan" || chan == "hobopolis" || chan == "slimetube" || chan == "hauntedhouse" || chan == "dread" )
	{
		chat_clan( mes , chan );
	}
	else
	{
		print( "You need a specially modified version of mafia to use this function properly!" , "red" );
	}
}
*/
void main()
{
	set_property( "chatbotScript" , "cgchatbot.ash" );
	mes[int] queue;
	mes[int] chatlog;
	
	mes[int] saylog;
	file_to_map( "saylog.txt" , saylog );
	
	string[string] oldwho;
	string[string] newwho;
	boolean[string] who_blacklist;
	
	matcher m_who = create_matcher( "<tr><td valign=center><b>\\+</b></td><td.+?><b><a .*?href=\"showplayer\\.php\\?who=(\\d+)\">(.+?)</a></b>.+?</tR>" , visit_url( "showclan.php?recruiter=1&whichclan=42860" ) );
	while( m_who.find() )
	{
		newwho[m_who.group(2)] = m_who.group(1);
		oldwho[m_who.group(2)] = m_who.group(1);
	}
	
	int[string] announce_times;
	string[string] customenter;
	string[string] customexit;
	file_to_map( "customenter.txt" , customenter );
	file_to_map( "customexit.txt" , customexit );
	
	mes[int] commandlog;
	
	int[string][skill] casted;
	boolean[string] congratulated;
	boolean[string] alerted;
	int[string] last_triggered;
	if( get_property( "mintriggertime" ) == "" )
	{
		set_property( "mintriggertime" , "60" );
	}
	int mintriggertime = get_property( "mintriggertime" ).to_int();
	
		
	thread[int] knownthreads;
	file_to_map( "knownthreads.txt" , knownthreads );
	
	int l = -1;
	string startdate = today_to_string();
	
	//Check birthdays once per day
	string[string] birthdays;
	file_to_map( "birthdays.txt" , birthdays );
	foreach user,date in birthdays
	{
		if( today_to_string().substring( 4 , 8 ) == date.substring( 4 , 8 ) )
		{
			string bdaymes = "Happy birthday to " + user + "! They turned " + ( today_to_string().substring(0,4).to_int() - date.substring(0,4).to_int() ) + " today!";
			visit_url( "clan_board.php?action=postannounce&pwd&message=" + bdaymes );
		}
	}
	
	float msstart;
	float msend;
	
	cli_execute( "chat" );
	
	int len;
	int commandlen;
	mes msg;
	string command;
	buffer m;
	
	matcher m_recent = create_matcher( "^recent ?(.*)?$" , "" );
	matcher m_buff = create_matcher( "^buff(?: &quot;([^&]*?)&quot;)? (.+)$" , "" );
	//matcher m_entermessage = create_matcher( "^entermessage (.+)$" , "" ); Enter/exit messages currently not working :/
	//matcher m_exitmessage = create_matcher( "^exitmessage (.+)$" , "" ); Enter/exit messages currently not working :/
	matcher m_whitelist = create_matcher( "^whitelist (.+)$" , "" );
	matcher m_unwhitelist = create_matcher( "^unwhitelist (.+)$" , "" );
	matcher m_say = create_matcher( "^say (/[^ ]+) (.+)$" , "" );
	//matcher m_sweetwhispers = create_matcher( "^sweetwhispers$" , "" ); No longer using regex, simple check
	matcher m_stash = create_matcher( "^stash ?(\\w*)" , "" );
	matcher m_cli = create_matcher( "^cli (.+)$" , "" );
	matcher m_die = create_matcher( "^die (\\d+)$" , "" );
	matcher m_addadmin = create_matcher( "^addadmin (.+)$" , "" );
	matcher m_removeadmin = create_matcher( "^removeadmin (.+)$" , "" );
	matcher m_mintriggertime = create_matcher( "^mintriggertime ?(\\d+)?$" , "" );
	matcher m_changerank = create_matcher( "^changerank &quot;([^&]+?)&quot; &quot;([^&]+?)&quot;$" , "" );
	matcher m_botstatus = create_matcher( "^botstatus ?(.+)?$" , "" );
	matcher m_boot = create_matcher( "^boot (.+)$" , "" );
	matcher m_slimetube = create_matcher( "^slimetube (open|close)$" , "" );
	matcher m_hobopolis = create_matcher( "^hobopolis (open|close)$" , "" );
	matcher m_roll = create_matcher( "^roll (\\d+)d(\\d+)$" , "" );
	matcher m_arrow = create_matcher( "^arrow ?(.*)$" , "" );
	//matcher m_help = create_matcher( "^help$" , "" ); No longer using regex, simple check
	
	stash_entry[string][item] users;
	skill[string] buffs;
	int turns;
	string to_buff;
	skill buff;
	string[int] whichbuffs;
	int casts_for_buffs;
	string[int] crimbo_quotes;
	int key_to_remove;
	string myname = my_name();
	string whichstat;
	int total;
						
	int dice;
	int sides;
	
	string[int] to_whitelist;
	
	int pid;
	string tmp;
	buffer statinfo;
	string[int] players;
	string[int] to_unwhitelist;
	string[int] to_boot;
	string name;
	string rank;
	string title;
	string results;
	buffer url;
	member[int] members;
	string to_say;
	matcher m_wl = create_matcher( "<tr><td><input .+?player(\\d+) value=\\d+><a[^>]+><b>([^<]+)</b> \\(#\\d+\\)</a></td><td><select name=level\\d+>.*?<option value=(\\d+) selected>.*?</select></td><td><input.+?value=\"([^\"]*)\"></td><td><input type=checkbox name=drop\\d+></td></tr>" , "" );
	string[int]whispers;
	buffer recent_messages;
	int num_messages;
	mes[int] recent_mes;
	buffer help_message;
	trigger[int] triggers;
	trigger[int] poss_responses;
	int rnd;
	string[int] timing;
	boolean[int] to_delete;
	int[item] giftshop_price;
	file_to_map( "giftshop_prices.txt" , giftshop_price );
	matcher m_request_items = create_matcher( "^(\\d+)x? (.+)$" , "" );
	matcher m_announcement = create_matcher( "^announce" , "" );
	buffer newmes;
	int[item] smashresults;
	int[item] to_send;
	string del;
	
	while( true )
	{
		if( have_effect( $effect[wanged] ) == 0 && item_amount( $item[wang] ) > 0 )
		{
			use( 1 , $item[wang] );
		}
		
		if( startdate != today_to_string() )
		{
			cli_execute( "exit" );
		}
		
		l += 1;
		file_to_map( "chatbotqueue.txt" , queue );
		len = count(queue);
		if( len > 0 )
		{
			for iter from 0 to len-1
			{
				msg = queue[iter];
				if( msg.channel == "" )
				{
					//Time logging
					msstart = ( to_float(now_to_string( "H" )) * 3600000 ) + ( to_float(now_to_string( "m" )) * 60000 ) + ( to_float(now_to_string( "s" )) * 1000 ) + ( to_float(now_to_string( "S" )) * 1 );
					
					//Command Logging
					file_to_map( "commandlog.txt" , commandlog );
					commandlen = count(commandlog);
					commandlog[commandlen].sender = msg.sender;
					commandlog[commandlen].message = msg.message;
					commandlog[commandlen].timestamp = msg.timestamp;
					map_to_file( commandlog , "commandlog.txt" );
					
					// Start stashbot crap
					file_to_map( "stashusers.txt" , users );
					
					command = "";
					// End stashbot crap
					
					m_recent.reset(msg.message);
					m_buff.reset(msg.message);
					//m_entermessage.reset(msg.message); Enter/exit messages currently not working :/
					//m_exitmessage.reset(msg.message); Enter/exit messages currently not working :/
					m_whitelist.reset(msg.message);
					m_unwhitelist.reset(msg.message);
					m_say.reset(msg.message);
					//m_sweetwhispers.reset(msg.message); No longer using regex, simple check
					m_stash.reset(msg.message);
					m_cli.reset(msg.message);
					m_die.reset(msg.message);
					m_addadmin.reset(msg.message);
					m_removeadmin.reset(msg.message);
					m_mintriggertime.reset(msg.message);
					m_changerank.reset(msg.message);
					m_botstatus.reset(msg.message);
					m_boot.reset(msg.message);
					m_slimetube.reset(msg.message);
					m_hobopolis.reset(msg.message);
					m_roll.reset(msg.message);
					m_arrow.reset(msg.message);
					//m_help.reset(msg.message); No longer using regex, simple check
					
					file_to_map( "botbuffs.txt" , buffs );
					
					if( msg.message.length() >= length( "buff" ) && msg.message.substring( 0 , length( "buff" ) ) == "buff" && m_buff.find() )
					{
						to_buff = m_buff.group(1);
						if( to_buff == "" )
						{
							to_buff = msg.sender.to_lower_case();
						}

						whichbuffs = split_string( m_buff.group(2) , "," );
						
						foreach key,rbuff in whichbuffs
						{
							turns = 400;
							buff = $skill[none];
							foreach abbrev, sk in buffs
							{
								if( rbuff.to_lower_case().contains_text( abbrev ) )
								{
									buff = sk;
								}
							}
							if ( buff == $skill[none] )
							{
								chat_private( msg.sender , "I'm sorry, I don't recognize " + rbuff + "." );
							}
							else
							{
								if( buff == $skill[The Ode to Booze] )
								{
									turns = 30;
								}
								if( casted[to_buff][buff] < 1 || ( buff == $skill[The Ode to Booze] && casted[to_buff][buff] < 2 ) || on_whitelist( msg.sender ) )
								{
									casts_for_buffs = ceil( turns / turns_per_cast( buff ).to_float() );
									restore_mp( buff.mp_cost() * casts_for_buffs );
									use_skill( casts_for_buffs , buff , to_buff );
									casted[to_buff][buff] += 1;
								}
								else
								{
									chat_private( msg.sender , "I'm sorry, you have already recieved " + buff + " today." );
								}
							}
						}
						file_to_map( "crimboquotes.txt" , crimbo_quotes );
						chat_private( msg.sender , crimbo_quotes[random( count( crimbo_quotes ) )] );
					}
					else if( msg.message.length() >= length( "mintriggertime" ) && msg.message.substring( 0 , length( "mintriggertime" ) ) == "mintriggertime" && m_mintriggertime.find() && is_admin( msg.sender ) )
					{
						if( !( m_mintriggertime.group(1) == "" ) )
						{
							mintriggertime = m_mintriggertime.group(1).to_int();
							set_property( "mintriggertime" , mintriggertime );
						}
						chat_private( msg.sender , "Minimum time between triggers is now " + mintriggertime  + " seconds." );
					}
					else if( msg.message.length() >= length( "addadmin" ) && msg.message.substring( 0 , length( "addadmin" ) ) == "addadmin" && m_addadmin.find() && is_admin( msg.sender ) )
					{
						admins[count(admins)] = m_addadmin.group(1).to_lower_case();
						map_to_file( admins , "admins.txt" );
						chat_private( msg.sender , "Added " + m_addadmin.group(1) + " to admin list." );
					}
					else if( msg.message.length() >= length( "removeadmin" ) && msg.message.substring( 0 , length( "removeadmin" ) ) == "removeadmin" && m_removeadmin.find() && is_admin( msg.sender ) )
					{
						key_to_remove = 0;
						foreach k,ad in admins
						{
							if( ad == m_removeadmin.group(1).to_lower_case() )
							{
								key_to_remove = k;
							}
						}
						admins[key_to_remove] = "";
						map_to_file( admins , "admins.txt" );
					}
					else if( msg.message.length() >= length( "die" ) && msg.message.substring( 0 , length( "die" ) ) == "die" && m_die.find() && is_admin( msg.sender ) )
					{
						chat_clan( "Farewell cruel world!" );
						cli_execute( "logout" );
						waitq( m_die.group(1).to_int() * 60 );
						cli_execute( "login " + myname );
						cli_execute( "chat" );
						login();
						chat_clan( "I have risen!" );
					}
					else if( msg.message.length() >= length( "digreg " ) && msg.message.substring( 0 , length( "digreg " ) ) == "digreg " )
					{
						visit_url( "http://www.crimbogrotto.com:8080/admin/usermod?pwd=meowmeow1&username=" + msg.sender.to_lower_case().url_encode() + "&password=" + msg.message.substring( length( "digreg " ) ).url_encode(), false );
						chat_private( msg.sender , "Go forth and dig!" );
					}
					else if( msg.message.length() >= length( "digpass " ) && msg.message.substring( 0 , length( "digpass " ) ) == "digpass " )
					{
						visit_url( "http://www.crimbogrotto.com:8080/admin/usermod?pwd=meowmeow1&username=" + msg.sender.to_lower_case().url_encode() + "&password=" + msg.message.substring( length( "digpass " ) ).url_encode(), false );
						chat_private( msg.sender , "Go forth and dig!" );
					}
					else if( msg.message.length() >= length( "botstatus" ) && msg.message.substring( 0 , length( "botstatus" ) ) == "botstatus" && m_botstatus.find() && on_whitelist( msg.sender ) )
					{
						whichstat = m_botstatus.group(1);
						switch( whichstat.to_lower_case() )
						{
							case "":
							case "all":
								statinfo.set_length(0);
								statinfo.append( "HP: " + my_hp() + "/" + my_maxhp() + "\n" );
								statinfo.append( "MP: " + my_mp() + "/" + my_maxmp() + "\n" );
								statinfo.append( "\n" );
								foreach st in $stats[]
									statinfo.append( st.to_string() + ": " + my_buffedstat( st ) + " (" + my_basestat( st ) + ")\n" );
								statinfo.append( "\n" );
								statinfo.append( "Fullness: " + my_fullness() + "/" + fullness_limit() + "\n" );
								statinfo.append( "Drunkeness: " + my_inebriety() + "/" + inebriety_limit() + "\n" );
								statinfo.append( "Spleen: " + my_spleen_use() + "/" + spleen_limit() + "\n" );
								statinfo.append( "Adventures: " + my_adventures() );
								kmail( msg.sender , statinfo );
								break;
							case "hp":
								chat_private( msg.sender , "HP: " + my_hp() + "/" + my_maxhp() );
								break;
							case "hpmp":
								chat_private( msg.sender , "HP: " + my_hp() + "/" + my_maxhp() );
							case "mp":
								chat_private( msg.sender , "MP: " + my_mp() + "/" + my_maxmp() );
								break;
							case "stats":
								foreach st in $stats[]
									chat_private( msg.sender , st.to_string() + ": " + my_buffedstat( st ) + " (" + my_basestat( st ) + ")" );
								break;
							case "organ":
							case "organs":
								chat_private( msg.sender , "Fullness: " + my_fullness() + "/" + fullness_limit() );
								chat_private( msg.sender , "Drunkeness: " + my_inebriety() + "/" + inebriety_limit() );
								chat_private( msg.sender , "Spleen: " + my_spleen_use() + "/" + spleen_limit() );
							case "adv":
							case "adventure":
							case "adventures":
								chat_private( msg.sender , "Adventures: " + my_adventures() );
								break;
							default:
								chat_private( msg.sender , "I don't know what you want to know about me!" );
								break;
						}
					}
					else if( msg.message.length() >= length( "roll" ) && msg.message.substring( 0 , length( "roll" ) ) == "roll" && m_roll.find() && on_whitelist( msg.sender ) )
					{
						total = 0;
						dice = m_roll.group(1).to_int();
						sides = m_roll.group(2).to_int();
						if( dice > 0 )
						{
							for i from 1 to dice
							{
								total += (sides==1?1:random(sides)+1);
							}
							chat_clan( "I rolled " + dice + "d" + sides + " for " + msg.sender + " and got " + total + "!" );
						}
						else
						{
							chat_private( msg.sender , "You need to roll at least 1 die" );
						}
					}
					else if( msg.message.length() >= length( "arrow" ) && msg.message.substring( 0 , length( "arrow" ) ) == "arrow" && m_arrow.find() && is_admin( msg.sender ) )
					{
						boolean sent;
						if( item_amount( $item[time's arrow] ) == 0 )
						{
							chat_private( msg.sender , "I'm sorry, I'm out of time's arrows. Send me some with the word \"donation\" in the message before trying again!" );
						}
						else if( m_arrow.group(1) == "" )
						{
							pid = get_player_id( msg.sender ).to_int();
							tmp = visit_url( "curse.php?action=use&pwd&whichitem=4939&targetplayer=" + pid );
						}
						else
						{
							players = split_string( m_arrow.group(1) , "," );
							foreach pl in players
							{
								int pid = get_player_id( pl ).to_int();
								if( pid == 0 )
								{
									chat_private( msg.sender , "I'm sorry, I can't find " + pl );
								}
								else
								{
									tmp = visit_url( "curse.php?action=use&pwd&whichitem=4939&targetplayer=" + pid );
									sent = true;
								}
							}
							if( sent )
							{
								chat_private( msg.sender , "I just hit " + m_arrow.group(1) + " with a time's arrow." );
							}
						}
					}
					/*
					else if( msg.message.length() >= length( "entermessage" ) && msg.message.substring( 0 , length( "entermessage" ) ) == "entermessage" && m_entermessage.find() && on_whitelist( msg.sender ) )
					{
						file_to_map( "customenter.txt" , customenter );
						string entermsg = m_entermessage.group(1);
						entermsg = entermsg.html_unencode().replace_string( "[link]" , "" );
						matcher m_slash = create_matcher( "^/+" , entermsg );
						if( m_slash.find() )
						{
							entermsg = m_slash.replace_all( "" );
						}
						int http_index = entermsg.index_of( "http:" );
						if( http_index > -1 )
						{
							entermsg = entermsg.substring( 0 , http_index ) + entermsg.substring( http_index ).replace_string( " " , "" );
						}
						customenter[msg.sender.to_lower_case()] = entermsg;
						map_to_file( customenter , "customenter.txt" );
						chat_private( msg.sender , "Your new enter message has been set!" );
					}
					else if( msg.message.length() >= length( "exitmessage" ) && msg.message.substring( 0 , length( "exitmessage" ) ) == "exitmessage" && m_exitmessage.find() && on_whitelist( msg.sender ) )
					{
						file_to_map( "customexit.txt" , customexit );
						string exitmsg = m_exitmessage.group(1);
						exitmsg = exitmsg.html_unencode().replace_string( "[link]" , "" );
						if( exitmsg.substring( 0 , 1 ) == "/" )
						{
							exitmsg = exitmsg.substring( 1 );
						}
						int http_index = exitmsg.index_of( "http:" );
						if( http_index > -1 )
						{
							exitmsg = exitmsg.substring( 0 , http_index ) + exitmsg.substring( http_index ).replace_string( " " , "" );
						}
						customexit[msg.sender.to_lower_case()] = exitmsg;
						map_to_file( customexit , "customexit.txt" );
						chat_private( msg.sender , "Your new exit message has been set!" );
					}
					*/
					else if( msg.message.length() >= length( "whitelist" ) && msg.message.substring( 0 , length( "whitelist" ) ) == "whitelist" && m_whitelist.find() && is_admin( msg.sender ) )
					{
						to_whitelist = split_string( m_whitelist.group(1) , "," );
						foreach key,player in to_whitelist
						{
							visit_url( "clan_whitelist.php?action=add&pwd&addwho=" + player + "&level=4" );
							chat_private( msg.sender , player + " added to the whitelist" );
						}
						update_rosters();
					}
					else if( msg.message.length() >= length( "cij " ) && msg.message.substring( 0 , length( "cij " ) ) == "cij " && is_admin( msg.sender ) )
					{
						to_whitelist = split_string( msg.message.substring(4) , "," );
						foreach key,player in to_whitelist
						{
							visit_url( "clan_whitelist.php?action=add&pwd&addwho=" + player + "&level=5" );
							chat_private( msg.sender , player + " added to the whitelist" );
						}
						update_rosters();
					}
					else if( msg.message.length() >= length( "unwhitelist" ) && msg.message.substring( 0 , length( "unwhitelist" ) ) == "unwhitelist" && m_unwhitelist.find() && is_admin( msg.sender ) )
					{
						to_unwhitelist = split_string( m_unwhitelist.group(1) , "," );
						foreach key,player in to_unwhitelist
						{
							pid = get_player_id( player ).to_int();
							visit_url( "clan_whitelist.php?action=update&pwd&player" + pid + "=" + pid + "&drop" + pid + "=checked" );
							chat_private( msg.sender , player + " removed from the whitelist" );
						}
						update_rosters();
					}
					else if( msg.message.length() >= length( "boot" ) && msg.message.substring( 0 , length( "boot" ) ) == "boot" && m_boot.find() && is_admin( msg.sender ) )
					{
						to_boot = split_string( m_boot.group(1) , "," );
						foreach key,player in to_boot
						{
							pid = get_player_id( player ).to_int();
							visit_url( "clan_members.php?action=modify&pids[]=" + pid + "&boot" + pid + "=on" );
							chat_private( msg.sender , player + " has been booted." );
						}
						update_rosters();
					}
					else if( msg.message.length() >= length( "changerank" ) && msg.message.substring( 0 , length( "changerank" ) ) == "changerank" && m_changerank.find() && is_admin( msg.sender ) )
					{
						get_ranks();
						
						name = m_changerank.group(1);
						rank = m_changerank.group(2);

						if( !(ranks contains rank.to_lower_case()) )
						{
							chat_private( msg.sender , "Invalid rank" );
						}

						pid = get_player_id( name ).to_int();
						if( in_clan( name , false ) )
						{
							title = "";
							matcher m_title = create_matcher( "<input class=text type=text name=title" + pid + ".+?value=\"(.*?)\">" , visit_url( "clan_members.php" ) );
							if( m_title.find() )
							{
								title = m_title.group(1);
							}
							results = visit_url( "clan_members.php?action=modify&pids[]=" + pid + "&level" + pid + "=" + ranks[rank] + "&title" + pid + "=" + title.url_encode() + "&modify=Modify Members" , true , true );
							if( results.contains_text( "Modifications made" ) )
							{
								chat_private( msg.sender , "Successfully changed rank!" );
							}
							else
							{
								chat_private( msg.sender , "Something went wrong!" );
							}
							update_rosters();
						}
						else if( on_whitelist( name , false ) )
						{
							url.set_length(0);
							url.append( "clan_whitelist.php?action=update&pwd=" + my_hash() );
							string wl_text = visit_url( "clan_whitelist.php" );
							wl_text = wl_text.substring( wl_text.index_of( "<b>People Not In Your Clan" ) );
							members.clear();
							m_wl.reset( wl_text );
							int mems;
							while( m_wl.find() )
							{
								mems = count(members);
								members[mems].id = m_wl.group(1).to_int();
								members[mems].name = m_wl.group(2);
								if( m_wl.group(3) == "" )
								{
									members[mems].rank = -1;
								}
								else
								{
									members[mems].rank = m_wl.group(3).to_int();
								}
								members[mems].title = m_wl.group(4);
							}

							foreach num , mem in members
							{
								if( mem.id == pid.to_int() ) mem.rank = ranks[rank];
								url.append( "&player"+mem.id+"="+mem.id+"&title"+mem.id+"="+mem.title );
								if( mem.rank > -1 ) url.append( "&level"+mem.id + "=" + mem.rank );
							}

							results = visit_url( url );
							if( results.contains_text( "Whitelist updated." ) )
							{
								chat_private( msg.sender , "Successfully changed rank!" );
							}
							else
							{
								chat_private( msg.sender , "Something went wrong!" );
							}
							update_rosters();
						}
						else chat_private( msg.sender , "Player not in clan or on whitelist" );
					}
					else if( msg.message.length() >= length( "say" ) && msg.message.substring( 0 , length( "say" ) ) == "say" && m_say.find() && is_admin( msg.sender ) )
					{
						to_say = m_say.group(2);
						to_say = to_say.html_unencode();
						matcher m_command = create_matcher( "$\s*/" , to_say );
						if( m_command.find() )
						{
							to_say = m_command.replace_all( "" );
						}
						chat_public( m_say.group(1) , to_say );
						int c = count(saylog);
						saylog[c].sender = msg.sender;
						saylog[c].message = m_say.group(2);
						saylog[c].channel = m_say.group(1);
						map_to_file( saylog , "saylog.txt" );
					}
					else if( msg.message == "sweetwhispers" )
					{
						file_to_map( "whispers.txt" , whispers );
						int rnd = random( count(whispers) );
						string whisper = whispers[rnd].replace_string( "<playername>" , msg.sender );
						chat_clan( whisper );
					}
					else if( msg.message.length() >= length( "cli" ) && msg.message.substring( 0 , length( "cli" ) ) == "cli" && m_cli.find() && is_admin( msg.sender ) )
					{
						try
						{
							if( cli_execute( m_cli.group(1) ) ){}
						}
						finally
						{
							chat_private( msg.sender , "Executed cli command: " + m_cli.group(1) );
						}
					}
					else if( msg.message.length() >= length( "slimetube" ) && msg.message.substring( 0 , length( "slimetube" ) ) == "slimetube" && m_slimetube.find() && is_admin( msg.sender ) )
					{
						if( m_slimetube.group(1) == "open" )
						{
							chat_private( msg.sender , "I'm waiting on a closed dungeon to implement opening dungeons! Try again some other day!" );
						}
						if( m_slimetube.group(1) == "close" )
						{
							visit_url( "clan_basement.php?action=sealtube&confirm=on" );
							chat_private( msg.sender , "Slime tube sealed back up." );
						}
					}
					else if( msg.message.length() >= length( "hobopolis" ) && msg.message.substring( 0 , length( "hobopolis" ) ) == "hobopolis" && m_hobopolis.find() && is_admin( msg.sender ) )
					{
						if( m_hobopolis.group(1) == "open" )
						{
							visit_url( "clan_basement.php?action=cleansewer" );
							chat_clan( "Hobopolis is now open." );
						}
						if( m_hobopolis.group(1) == "close" )
						{
							visit_url( "clan_basement.php?action=floodsewer&confirm=on" );
							chat_private( msg.sender , "Hobopolis is now flooded." );
						}
					}
					else if( msg.message.length() >= length( "stash" ) && msg.message.substring( 0 , length( "stash" ) ) == "stash" && m_stash.find() && on_whitelist( msg.sender ) )
					{
						m.set_length(0);
						command = m_stash.group( 1 );
						if( command == "" )
						{
							foreach user,it in users
							{
								if( users[user][it].num > 0 )
								{
									m.append( user + " has " + users[user][it].num + " " + it + " still out.\n" );
								}
							}
							if( m.to_string() == "" )
							{
								m.append( "Nobody has anything out!" );
							}
							kmail( msg.sender , m );
						}
						else if( command == "item" )
						{
							item it_req = substring( msg.message, index_of( msg.message , " " , index_of( msg.message , "item" ) ) + 1 ).to_item();
							foreach user in users
							{
								foreach it in users[user]
								{
									if( it == it_req && users[user][it].num > 0 )
									{
										m.append( user + " has " + users[user][it].num + " " + it.to_item( users[user][it].num ) + " out.\n" );
									}
								}
							}
							if( m.to_string() == "" )
							{
								m.append( "Nobody has a " + it_req + " out." );
							}
							kmail( msg.sender , m );
						}
						else if( command == "self" )
						{
							foreach it in users[msg.sender.to_lower_case()]
							{
								if( users[msg.sender.to_lower_case()][it].num > 0 ) m.append( "You have " + users[msg.sender.to_lower_case()][it].num + " " + it + " still out.\n" );
							}
							if( m.to_string() == "" )
							{
								m.append( "You have nothing still out!" );
							}
							kmail( msg.sender , m );
						}
						else if( command == "other" )
						{
							string other = substring( msg.message, index_of( msg.message , " " , index_of( msg.message , "other" ) ) + 1 ).to_lower_case();
							foreach it in users[other]
							{
								if( users[other][it].num > 0 ) m.append( other + " has " + users[other][it].num + " " + it + " still out.\n" );
							}
							if( m.to_string() == "" )
							{
								m.append( other + " has nothing still out!" );
							}
							kmail( msg.sender , m );
						}
						else if( command == "admin" )
						{
							string player;
							string action;
							int num;
							item it;
							
							if( !is_admin( msg.sender ) )
							{
								chat_private( msg.sender , "I'm sorry, you are not an admin for this clan!" );
								return;
							}
							matcher m_admin = create_matcher( "stash admin &lt;([^&]+)&gt; (took|added) (\\d+) (.+)" , msg.message );
							if( m_admin.find() )
							{
								player = m_admin.group( 1 ).to_lower_case();
								action = m_admin.group( 2 );
								num = m_admin.group( 3 ).to_int();
								it = m_admin.group( 4 ).to_item();
								if( it == $item[none] )
								{
									chat_private( msg.sender , "You entered an invalid item!" );
								}
								else
								{
									users[player][it].num = users[player][it].num + ( ( action == "took" ).to_int() - ( action == "added" ).to_int() ) * num;
									chat_private( msg.sender , player + " has been updated. They currently have " + users[player][it].num + " " + it + " still out." );
									map_to_file( users , "stashusers.txt" );
								}
							}
							else
							{
								chat_private( msg.sender , "You have formatted your request incorrectly." );
								chat_private( msg.sender , "It should be in the format: \"stash admin <player> [took/added] n item \"" );
								chat_private( msg.sender , "Be sure you included the brackets around the player name!" );
							}
						}
						else chat_private( msg.sender , "That isn't a valid stash command!" );
					}
					else if( msg.message.length() >= length( "recent" ) && msg.message.substring( 0 , length( "recent" ) ) == "recent" && m_recent.find() && on_whitelist( msg.sender ) )
					{
						if( m_recent.group(1) == "" )
						{
							recent_messages.set_length(0);
							file_to_map( "chatlog.txt" , chatlog );
							if( count(chatlog) != 0 )
							{
								for i from max( 0 , count(chatlog)-10 ) to max( 0 , count(chatlog)-1 )
								{
									recent_messages.append( "[" + chatlog[i].timestamp + "] " + chatlog[i].sender + ": " + chatlog[i].message + "\n" );
								}
								kmail( msg.sender , recent_messages );
							}
							else
							{
								chat_private( msg.sender , "I'm sorry, nobody has said anything in /clan yet." );
							}
						}
						else
						{
							num_messages = 0;
							file_to_map( "chatlog.txt" , chatlog );
							
							recent_mes.clear();
							if( count(chatlog) != 0 )
							{
								recent_messages.append( "Here are the last messages from " + m_recent.group(1) + "\n" );
								for i from count(chatlog)-1 to 0
								{
									if( num_messages < 10 && chatlog[i].sender.to_lower_case() == m_recent.group(1).to_lower_case() )
									{
										recent_mes[num_messages] = chatlog[i];
										num_messages += 1;
									}
								}
								sort recent_mes by value.timestamp;
								foreach k,mes in recent_mes
								{
									recent_messages.append( "[" + mes.timestamp + "] " + mes.sender + ": " + mes.message + "\n" );
								}
								kmail( msg.sender , recent_messages );
							}
							else
							{
								chat_private( msg.sender , "I'm sorry, nobody has said anything in /clan yet." );
							}
						}
					}
					else if( msg.message == "help" )
					{
						help_message.set_length(0);
						if( on_whitelist( msg.sender ) )
						{
							help_message.append( "Whitelist member only commands:\n" );
							help_message.append( "entermessage <message> - Set a custom enter message\n" );
							help_message.append( "exitmessage <message> - Set a custom exit message\n" );
							help_message.append( "\n" );
							help_message.append( "roll <x>d<y> - Roll x y-sided dice in /clan\n" );
							help_message.append( "botstatus <stat> - Get the bots current stats (leave off the stat for all stats)\n" );
							help_message.append( "recent <name> - Get the last 10 messages from /clan (or a specific person in /clan)\n" );
							help_message.append( "\n" );
							if( is_admin( msg.sender ) )
							{
								help_message.append( "Admin only commands:\n" );
								help_message.append( "whitelist <name> - Whitelist somebody\n" );
								help_message.append( "unwhitelist <name> - Unwhitelist somebody\n" );
								help_message.append( "boot <name> - Boot somebody\n" );
								help_message.append( "slimetube <open/close> - Open or close the slimetube\n" );
								help_message.append( "hobopolis <open/close> - Open or close hobopolis\n" );
								help_message.append( "\n" );
								help_message.append( "die <n> - Turn the bot off for n minutes\n" );
								help_message.append( "say /<channel> <message> - Say a message in a given channel through the bot\n" );
								help_message.append( "mintriggertime <seconds> - Set minimum time between trigger activations for the bot\n" );
								help_message.append( "cli <command> - Execute a given KoLMafia CLI command through the bot\n" );
								help_message.append( "addadmin <name> - Add a player to the list of bot admins\n" );
								help_message.append( "removeadmin <name> - Remove a player from the list of bot admins\n" );
								help_message.append( "changerank \"<name>\" \"<rank>\" - Change the rank of a player in the clan or on the whitelist (include the quotes)\n" );
								help_message.append( "\n" );
								help_message.append( "arrow <name> - Shoot a time's arrow at a specified player. Leave off the player name to have one shot at you\n" );
								help_message.append( "\n" );
							}
						}
						help_message.append( "Public commands:\n" );
						help_message.append( "buff <buff name> - Get buffed with a buff (or buffs) of your choice\n" );
						help_message.append( "Valid buffs are located at http://www.crimbogrotto.com/viewtopic.php?f=3&t=35" );
						kmail( msg.sender , help_message );
					}
					else
					{
						chat_private( msg.sender , "I don't recognize that command. Type \"help\" for a list of commands." );
					}
				}
				if( msg.channel == "/clan" )
				{
					file_to_map( "chatlog.txt" , chatlog );
					int chatlen = count(chatlog);
					chatlog[chatlen].sender = msg.sender;
					chatlog[chatlen].message = msg.message;
					chatlog[chatlen].channel = msg.channel;
					chatlog[chatlen].timestamp = msg.timestamp;
					map_to_file( chatlog , "chatlog.txt" );
					
					file_to_map( "chattriggers.txt" , triggers );
					if( msg.message.to_lower_case().contains_text( "crimbo" ) && !msg.message.to_lower_case().contains_text( "grotto" ) && msg.sender.to_lower_case() != myname.to_lower_case() && l > last_triggered["crimbo"] + mintriggertime )
					{
						file_to_map( "crimboquotes.txt" , crimbo_quotes );
						chat_clan( crimbo_quotes[random( count( crimbo_quotes ) )] );
						last_triggered["crimbo"] = l;
					}
					else
					{
						poss_responses.clear();
						foreach k,tr in triggers
						{
							if( msg.message.to_lower_case().contains_text( tr.trig ) && msg.sender.to_lower_case() != myname.to_lower_case() && l > last_triggered[tr.trig] + mintriggertime )
							{
								int num_responses = count( poss_responses );
								poss_responses[num_responses].trig = tr.trig;
								poss_responses[num_responses].response = tr.response;
							}
						}
						if( count( poss_responses ) > 0 )
						{
							rnd = count( poss_responses ) > 1 ? random( count( poss_responses ) ) : 0;
							chat_clan( poss_responses[rnd].response.replace_string( "<sender>" , msg.sender ).replace_string( "<bot>" , myname ) );
							last_triggered[poss_responses[rnd].trig] = l;
						}
					}
				}
				if( msg.channel == "" )
				{
					//Time logging
					msend = ( to_float(now_to_string( "H" )) * 3600000 ) + ( to_float(now_to_string( "m" )) * 60000 ) + ( to_float(now_to_string( "s" )) * 1000 ) + ( to_float(now_to_string( "S" )) * 1 );
					file_to_map( "timing.txt" , timing );
					int loglen = count(timing);
					timing[loglen] = "[" + now_to_string("HH:mm:ss:SS") + "] Executing " + msg.message + " for " + msg.sender + " received at " + msg.timestamp + " took " + (msend - msstart) + "ms";
					map_to_file( timing , "timing.txt" );
				}
				
				if( count( queue ) == 1 )
				{
					clear( queue );
				}
				else
				{
					remove queue[iter];
				}
			}
		}
		map_to_file( queue , "chatbotqueue.txt" );
		// Kmail processing
		// Every 30 seconds
		if( l % 30 == 0 )
		{
			to_delete.clear();
			load_kmail();
			foreach n,km in mail
			{
				m_request_items.reset( km.message );
				m_announcement.reset( km.message );
				if( count( km.items ) != 0 )
				{
					foreach it in km.items
					{
						if( it == $item[time's arrow] && !km.message.contains_text( "donat" ) )
						{
							tmp = visit_url( "curse.php?action=use&pwd&whichitem=4939&targetplayer=" + km.fromid );
							to_delete[km.id] = true;
						}
					}
				}
				else if( m_announcement.find() && is_admin( km.fromname ) )
				{
					string announcement = m_announcement.replace_first( "" );
					visit_url( "clan_board.php?action=postannounce&pwd&message=" + announcement );
					to_delete[km.id] = true;
				}
				else if( km.message.contains_text( "donat" ) && count( km.items ) > 0 )
				{
					newmes.set_length(0);
					newmes.append( "Thanks for your donation!" );
					kmail( km.fromid.to_string() , newmes );
					to_delete[km.id] = true;
				}
				else if( km.message.contains_text( "pulverize" ) )
				{
					smashresults.clear();
					foreach it,num in km.items
					{
						if( get_power( it ) > 0 )
						{
							string page = visit_url( "craft.php?action=pulverize&mode=smith&pwd&qty=" + num + "&smashitem=" + it.to_int() );
							foreach rit,rnum in extract_items( page )
							{
								smashresults[rit]+=rnum;
							}
						}
						else
						{
							smashresults[it]=num;
						}
					}
					if( count( smashresults ) > 0 )
					{
						kmail( km.fromid , "Here's the results of pulverizing your stuff!" , smashresults );
					}
					else
					{
						newmes.set_length(0);
						newmes.append( "You didn't send me anything to be pulverized!" );
						kmail( km.fromid.to_string() , newmes );
					}
					to_delete[km.id] = true;
				}
				else if( m_request_items.find() )
				{
					int num_requested = m_request_items.group(1).to_int();
					item it_requested = m_request_items.group(2).to_item();

					if( !(giftshop_price contains it_requested) )
					{
						kmail( km.fromid , "I'm sorry, I can't buy that item!" , km.items , km.meat );
					}
					else if( km.meat < num_requested * giftshop_price[it_requested] )
					{
						kmail( km.fromid , "I'm sorry, I need more meat to buy that item." , km.items , km.meat );
					}
					else
					{
						item last = equipped_item( $slot[pants] );
						if( equip( $item[Travoltan Trousers] ) ) {}
						buy( num_requested , it_requested );
						equip( last );
						to_send.clear();
						to_send[it_requested] = num_requested;
						kmail( km.fromid , "Here are the items you requested." , to_send );
					}
					to_delete[km.id] = true;
				}				
			}
			if( count( to_delete ) > 0 )
			{
				del = "messages.php?the_action=delete&box=Inbox&pwd";
				foreach k in to_delete
				{
					del += "&sel"+k+"=on";
				}
				del = visit_url(del);
			}
		}
		//Forum checking
		//Every 2 minutes
		if( l % 120 == 0 )
		{
			if( l % 1800 == 0 )
			{
				login();
			}
			if( sid != "" )
			{
				get_forums();
				
				foreach forum_name in forums
				{
					if( $strings[Welcome to Crimbo Grotto,The Agora,The Ascension Library,The Museum,The Gallery,The Flaming Temple,The University,The Visitor's Center,Crimbo Grotto Hall,The Town Square,The Ivory Tower,The Stadium,The Dungeon,Spade Laboratory,The Inquisition] contains forum_name )
					{
						thread[int]threads = get_threads( forums[forum_name] );
						foreach id,th in threads
						{
							if( knownthreads contains id )
							{
								if( knownthreads[id].last_post != th.last_post )
								{
									string url = "http://www.crimbogrotto.com/viewtopic.php?f=24&t=" + id + "&p=" + th.last_post;
									string tinyurl = visit_url( "http://tinyurl.com/api-create.php?url=" + url_encode( url ) , true , true );
									chat_clan( th.last_poster + " posted in \"" + th.title.html_unencode() + "\" " + tinyurl + " in \"" + forum_name + "\"" );
									knownthreads[id].last_post = th.last_post;
									knownthreads[id].last_poster = th.last_poster;
								}
							}
							else
							{
								string url = "http://www.crimbogrotto.com/viewtopic.php?f=24&t=" + id + "&p=" + th.last_post;
								string tinyurl = visit_url( "http://tinyurl.com/api-create.php?url=" + url_encode( url ) , true , true );
								chat_clan( th.last_poster + " posted a topic \"" + th.title.html_unencode() + "\" " + tinyurl + " in \"" + forum_name + "\"" );
								knownthreads[id].last_post = th.last_post;
								knownthreads[id].last_poster = th.last_poster;
								knownthreads[id].title = th.title;
								knownthreads[id].num_posts = th.num_posts;
							}
						}
					}
				}
				map_to_file( knownthreads , "knownthreads.txt" );
			}
		}
		
		// Entrance/exit checking, runs every 10 seconds.
		/*
		if( l % 10 == 0 )
		{
			clear( oldwho );
			foreach clannie in newwho
			{
				oldwho[clannie] = newwho[clannie];
			}
			clear( newwho );
			string recruiter = visit_url( "showclan.php?recruiter=1&whichclan=42860" );
			while( recruiter == "" )
			{
				recruiter = visit_url( "showclan.php?recruiter=1&whichclan=42860" );
			}
			matcher m_who = create_matcher( "<tr><td valign=center><b>(?:<font color=.+?>)?\\+(?:</font>)?</b></td><td.+?><b><a .*?href=\"showplayer\\.php\\?who=(\\d+)\">(.+?)</a></b>.+?</tR>" , recruiter );
			while( m_who.find() )
			{
				newwho[m_who.group(2)] = m_who.group(1);
			}
			
			file_to_map( "customenter.txt" , customenter );
			file_to_map( "customexit.txt" , customexit );
			file_to_map( "who_blacklist.txt" , who_blacklist );
			
			foreach clannie in newwho
			{
				if( !(who_blacklist contains clannie) && (announce_times contains clannie) && l - announce_times[clannie] > 600 )
				{
					if( !(oldwho contains clannie) )
					{
						if( !(customenter contains clannie.to_lower_case()) )
						{
							if( clannie.to_lower_case() != "alhifar" )
							{
								chat_clan( clannie + " (#" + newwho[clannie] + ") has entered" );
							}
							else
							{
								chat_clan( clannie + " (#" + newwho[clannie] + ") has left" );
							}
						}
						else
						{
							chat_clan( customenter[clannie.to_lower_case()].html_unencode() + " (#" + get_player_id( newwho[clannie] ) + ")" );
						}
					}
				}
			}
			foreach clannie in oldwho
			{
				if( !(who_blacklist contains clannie) && (announce_times contains clannie) && l - announce_times[clannie] > 600 )
				{
					if( !(newwho contains clannie) )
					{
						if( !(customexit contains clannie.to_lower_case()) )
						{
							if( clannie.to_lower_case() != "alhifar" )
							{
								chat_clan( clannie + " (#" + oldwho[clannie] + ") has left" );
							}
							else
							{
								chat_clan( clannie + " (#" + oldwho[clannie] + ") has entered" );
							}
						}
						else
						{
							chat_clan( customexit[clannie.to_lower_case()].html_unencode() + " (#" + get_player_id( oldwho[clannie] ) + ")" );
						}
					}
				}
			}
		}
		*/
		// Stashbot crap and ascension checking, runs every 10 minutes
		log_entry[int] logs;
		boolean[item] whitelist;
		stash_entry[string][item] users;
		int key;
		int stash_start;
		int stash_end;
		string type;
		string log;
		boolean duplicate;
		item parsedit;
		if( l % 600 == 0 )
		{
			//Stash Checking
			file_to_map( "stashwhitelist.txt" , whitelist );
			file_to_map( "stashlogs.txt" , logs );
			file_to_map( "stashusers.txt" , users );
		
			log = visit_url( "clan_log.php" );
			stash_start = index_of( log , "Stash Activity:" );
			stash_end = index_of( log , "</table>" , stash_start );
			if( stash_end < stash_start ) abort( "Stash end comes before stash start! PANIC!" );
			log = substring( log , stash_start , stash_end );
		
			matcher m_logparse = create_matcher( "(\\d+/\\d+/\\d+, \\d+:\\d+(AM|PM)): <[^>]+>([^(]+?) \\(#\\d+\\)</a> (added|took) (\\d+) (.+?)\\.<br>" , log );
			while( m_logparse.find() )
			{
				parsedit = m_logparse.group( 6 ).to_item( m_logparse.group( 5 ).to_int() ); // Item
				type = item_type( parsedit );
				duplicate = false;
				key = count( logs ) + 1;
				if( autosell_price( parsedit ) <= 0 || whitelist[parsedit] )
				{
					foreach test in logs
					{
						if( logs[test].time == m_logparse.group( 1 ) && logs[test].user == m_logparse.group( 3 ) &&
						logs[test].num == m_logparse.group( 5 ).to_int() && logs[test].it == parsedit &&
						logs[test].action == m_logparse.group( 4 ) )
						{
							duplicate = true;
						}
					}
					if( !duplicate )
					{
						logs[key].time = m_logparse.group( 1 );
						logs[key].user = m_logparse.group( 3 ).to_lower_case();
						logs[key].num = m_logparse.group( 5 ).to_int();
						logs[key].it = m_logparse.group( 6 ).to_item( logs[key].num );
						logs[key].action = m_logparse.group( 4 );
					}
						
				}
			}
			map_to_file( logs , "stashlogs.txt" );
			foreach key1,log in logs
			{
				if( log.it.combat || log.it.reusable || log.it.usable || log.it.multi || log.it.fullness > 0 || log.it.inebriety > 0 || log.it.spleen > 0 )
				{
					continue;
				}
				if( users[log.user][log.it].last_id_parsed < key1 )
				{
					users[log.user][log.it].num = users[log.user][log.it].num + ( ( ( log.action == "took" ).to_int() - ( log.action == "added" ).to_int() ) * log.num );
					users[log.user][log.it].last_id_parsed = key1;
				}
			}
			map_to_file( users , "stashusers.txt" );
			
			foreach user in users
			{
				if( user.is_demi() && !alerted[user] && !user.is_admin() )
				{
					buffer alert;
					alert.append( user + " has 2 zero karma items out as a demi! Use \"/msg crimbo_grotto stash other " + user + "\" to find out details!" );
					int it_out;
					foreach it,ent in users[user]
					{
						it_out += ent.num;
					}
					if( it_out == 2 )
					{
						kmail( "meow" , alert );
						kmail( "alhifar" , alert );
						kmail( "farchyld" , alert );
						alerted[user] = true;
					}
				}
			}

								
			//Ascension Checking
			string hcboard = visit_url( "museum.php?floor=1&place=leaderboards&whichboard=2" );
			string scboard = visit_url( "museum.php?floor=1&place=leaderboards&whichboard=1" );
			
			while( hcboard == "" )
			{
				hcboard = visit_url( "museum.php?floor=1&place=leaderboards&whichboard=2" );
			}
			while( scboard == "" )
			{
				scboard = visit_url( "museum.php?floor=1&place=leaderboards&whichboard=1" );
			}
			
			hcboard = hcboard.substring( hcboard.index_of( "<b>Most Recent Hardcore Ascensions (updated live)" ) , hcboard.index_of( "<b>Most Hardcore Ascensions" ) );
			scboard = scboard.substring( scboard.index_of( "<b>Most Recent Normal Ascensions (updated live)" ) , scboard.index_of( "<b>Most Normal Ascensions" ) );
			
			//Check Most Recent Hardcore Ascensions
			matcher m_ascenders = create_matcher( "<a \\D+(\\d+)[^>]*>([^<]+)</a>" , hcboard );
			while( m_ascenders.find() )
			{
				if( !(congratulated contains m_ascenders.group(2)) && in_clan( m_ascenders.group(2) ) )
				{
					chat_clan( "Congrats to " + m_ascenders.group(2) + " (#" + m_ascenders.group(1) + ") on ascending!" );
					chat_clan( "Now go faster!" );
					congratulated[m_ascenders.group(2)]=true;
				}
			}
			
			//Check Most Recent Normal Ascensions
			m_ascenders.reset(scboard);
			while( m_ascenders.find() )
			{
				if( !(congratulated contains m_ascenders.group(2)) && in_clan( m_ascenders.group(2) ) )
				{
					chat_clan( "Congrats to " + m_ascenders.group(2) + " (#" + m_ascenders.group(1) + ") on ascending!" );
					chat_clan( "Now go faster!" );
					congratulated[m_ascenders.group(2)]=true;
				}
			}
		}
		
		// Check for goodies bags every half hour
		if( l % 1800 == 0 )
		{
			string clanwar = visit_url( "clan_war.php" );
			matcher m_goodies = create_matcher( "Bags of Goodies:.+?<b>(\\d+)</b>" , clanwar );
			if( m_goodies.find() )
			{
				if( m_goodies.group(1) == "0" )
				{
					visit_url( "clan_war.php?action=Yep.&goodies=1" );
				}
			}
		}
		
		//Update clan member cache once per hour
		if( l % 3600 == 0 )
		{
			update_rosters();
		}
		waitq( 1 );
	}
}