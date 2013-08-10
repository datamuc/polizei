#!/opt/perl/perls/perl-5.14.0/bin/perl

# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <m@rbfh.de> wrote this file. As long as you retain this notice you can
# do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return
# Danijel Tasov
# ----------------------------------------------------------------------

use 5.014;
use strict;
use Mojo::UserAgent;
use Data::Dumper::Concise;
use Digest::SHA;
use XML::Feed;
use Devel::Peek;
use URI;
use Encode;
use DBI;
use utf8;
use feature 'unicode_strings';

my $db = DBI->connect("dbi:SQLite:/home/danielt/log/polizei.db")
    or die($DBI::errstr);
my $insert = $db->prepare(q{
    insert or ignore into meldungen
    (id, title, meldung, ts) values (?,?,?,datetime('now'))
});
my $feed = "http://www.polizei.bayern.de/muenchen/polizei.rss";
my $myfeed = XML::Feed->new( 'RSS' );
$myfeed->title("Polizei München Presseberichte" );
$myfeed->link("http://www.polizei.bayern.de/muenchen/news/presse/aktuell/index.html");

my $c = Mojo::UserAgent->new;

$c->get($feed)->res->dom->find("item link")->each(sub{
    buildItems($_->text);
});

print Encode::encode('utf-8', $myfeed->as_xml);

sub buildItems {
    my $link = shift;
    my $dom = $c->get($link)->res->dom;

    $dom->find("img")->each(sub {
        my $img = shift;
        my $src = $img->attrs->{src};
        my $newsrc = URI->new_abs($src, $link)->as_string;
        $img->attrs(src => $newsrc);
    });

    my @titles = map { $_->text } $dom->find("div.inhaltUeberschriftFolgeseiten2")->each;
    my @contents = map { $_->content_xml } $dom->find("div.inhaltText")->each;


    if(@titles != @contents) {
        warn("Ooops: number of titles != number of contents");
        return;
    }

    for my $i (0..$#titles) {
        #Dump($contents[$i]);
        my $guid = Digest::SHA::sha1_hex($contents[$i]);
        $contents[$i] = Encode::decode('utf-8', $contents[$i]);
        my $item = XML::Feed::Entry->new('RSS');
        next unless (length($titles[$i]) or length($contents[$i]));
        $item->title($titles[$i]);
        $item->content($contents[$i]);
        $item->link('http://data.rbfh.de/p.cgi/'.$guid);
        $item->id($guid);
        $myfeed->add_entry( $item );
        $insert->execute($guid, $titles[$i], $contents[$i]);
    }


}

