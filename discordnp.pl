#!/usr/bin/env perl

use Mojo::Base -base;
use Mojo::WebService::LastFM;
use Mojo::Discord;
use Mojo::IOLoop;
use Config::Tiny;

# Read the config file
# Default to "config.ini" unless one is passed in as an argument
my $config = Config::Tiny->new;
my $config_file = $ARGV[0] // 'config.ini';
$config = Config::Tiny->read( $config_file, 'utf8' );
say localtime(time) . " - Loaded Config: $config_file";

# Instantiate the current and previously played tracks to empty strings
my $np = "";
my $last_played = "";

# How often are we polling Last.FM for new statuses?
my $interval = $config->{'lastfm'}->{'interval'};

# Get the user's Discord token from the config
my $discord_token = $config->{'discord'}->{'token'};
$discord_token =~ s/^(?:token:)?"?"?(.*?)"?"?$/$1/;  # Extract the actual token if they user copypasted the entire field from their browser.

# Get the user's Last.FM API Key from the config
my $lastfm_key = $config->{'lastfm'}->{'api_key'};
$lastfm_key =~ s/^"?(.*?)"?$/$1/;

# Set up the Mojo::WebService::LastFM object with the provided key
my $lastfm = Mojo::WebService::LastFM->new(
    api_key     => $lastfm_key
);

# Set up the Mojo::Discord object with the provided token
my $discord = Mojo::Discord->new(
    # Ctrl+Shift+I and type localStorage.token in the console to get the user token.
    'token'         => $discord_token,
    'token_type'    => 'Bearer',
    'name'          => 'Discord Now Playing',
    'url'           => 'https://github.com/vsterminus',
    'version'       => '1.0',
    'verbose'       => $config->{'discord'}->{'verbose'},
    'reconnect'     => 0,
    'callbacks'     => {    # We really only need to know when Discord is connected and disconnected. Nothing else matters here.
        'READY'     => \&on_ready,
        'FINISH'    => \&on_finish, 
    },
);

# Poll Last.FM and update the user's Discord status if the track has changed.
sub update_status
{
    # Mojo::WebService::LastFM lets us optionally specify a format to return the results in.
    # Without it we would just get a hashref back containing all of the values.
    # For this script all we need is Artist - Title.
    # 
    # This call is also optionally non-blocking if a callback function is provided, which we are doing.
    $lastfm->nowplaying({   user     => $config->{'lastfm'}->{'username'}, 
		    #format   => "%artist% - %title%", 
                            callback => sub 
    {
        my $nowplaying = shift;

        if ( defined $nowplaying )
        {
		if ( $nowplaying->{'nowplaying'} eq 'true' )
		{
                # If we received a valid response from Last.FM and a new song is playing, update our info.
                $np = $nowplaying->{'artist'} . ' - ' . $nowplaying->{'title'};

                # Now connect to discord. Receiving the READY packet from Discord will trigger the status update automatically.
                $discord->init(); 
		}
        }
        else
        {
            say localtime(time) . " - Unable to retrieve Last.FM data.";
        }    
    }});

    

}

# After connecting to Discord it will send a READY packet full of information.
# We don't care what is in that packet, only that Discord accepted our connection.
# It tells us that it is now safe to send a status update.
sub on_ready
{
    my ($hash) = @_;

    $discord->status_update({
        'name' => $np,
        'type' => 2, # Listening to...
        'details' => 'last.fm/user/' . $config->{'lastfm'}{'username'},
        'state' => 'github.com/vsTerminus/Discord-NP'
    });

    say localtime(time) . " - Status Updated: $np";
    $last_played = $np;

    # Once the status update has been sent, immediately disconnect from Discord again.
    # This ensures that we won't block Android notifications.
    # (If we stayed connected Discord would think we were actively watching the chat and would not trigger the push notification to mobile clients)
     
   
    $discord->disconnect();
}

# This triggers when Discord disconnects.
# We could do more validation here, but for now this is enough.
sub on_finish
{
    say localtime(time) . " - Disconnected from Discord.";
}

# This is the first line of code executed by the script (aside from setting variables).
# It should trigger the first poll to Last.FM immediately.
update_status();

# Now set up a recurring timer to periodically poll Last.FM for new updates.
Mojo::IOLoop->recurring($config->{'lastfm'}->{'interval'} => sub { update_status(); });

# Start the IOLoop. This will connect to discord and begin the LastFM timers.
# Anything below this line will not execute until the IOLoop completes (which is never).
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
