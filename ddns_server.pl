#!/usr/bin/perl

use strict;
use warnings;

use IO::Socket;
use Digest::MD5 qw(md5 md5_hex md5_base64);

use constant {
    DDNS_PORT => 153,
    DDNS_SALT => 'v[)P\bP=s<fsK4/7',
    BIND_DOMAINS_DIR => '/etc/bind/local'
};


my $server = IO::Socket::INET->new(
        LocalPort => DDNS_PORT,
        Type      => SOCK_STREAM,
        Reuse     => 1,
        Listen    => 10 )   # or SOMAXCONN
    or die "Couldn't be a tcp server on port " . DDNS_PORT . ": $@\n";

while (my $client = $server->accept()) {
    my $ip = $client->peerhost();

    my $rand = rand();
    print $client "$rand\n";

    my $chunk;
    my $response = '';
    while (substr($response, -1) ne "\n" and length($response) < 128 and $chunk = <$client>) {
        $response .= $chunk;
    }
    close $client;
    $response = substr($response, 0, -1);

    my ($domain, $md5) = split(/:/, $response);

    #my $domain_escaped = quotemeta($domain);
    #if(!grep(/$domain_escaped/, @domains)) {
    #    next;
    #}

    if($domain !=~ /^[\w\.]+$/) {
        print "Invalid domain!\n";
        next;
    }

    if(md5_hex($rand . $domain . DDNS_SALT) ne $md5) {
        next;
    }

    if(! -e "db/$domain") {
        next;
    }

    my $cache_sn;
    if(-e "cache/$domain" and open(my $f_cache, '<', "cache/$domain" )) {
        my $cache = <$f_cache>;
        close($f_cache);

        (my $cache_ip, $cache_sn) = split(/:/, $cache);

        if($cache_ip eq $ip) {
           print "IP not changed.\n";
           next;
        }
    }
    else {
        $cache_sn = '';
    }

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime();
    $mon += 1;
    $year += 1900;

    my $sn = sprintf("%d%02d%02d", $year, $mon, $mday);

    if($sn eq substr($cache_sn, 0, 8)) {
       $sn .= sprintf("%02d", substr($cache_sn, 8) + 1);
    }
    else {
       $sn .= '01';
    }

    if(open(my $f_cache, '>', "cache/$domain")) {
       print $f_cache "$ip:$sn";
       close($f_cache);
    }

    my $zone_reloaded = 0;
    if(open(my $f_zone_in, '<' . "db/$domain")) {
        if(open(my $f_zone_out, '>' . BIND_DOMAINS_DIR . "/$domain")) {
            while(<$f_zone_in>) {
                $_ =~ s/__SERIAL__/$sn/g;
                $_ =~ s/__IP__/$ip/g;
                print $f_zone_out $_;
            }
            $zone_reloaded = 1;
            close($f_zone_out);
        }
        close($f_zone_in);
    }

#    if($zone_reloaded) {
#        system("rndc", "reload", $domain);
#    }
}

close($server);
