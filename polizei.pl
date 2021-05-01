#!/opt/perl/perls/perl-5.22.0/bin/perl

# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <m@rbfh.de> wrote this file. As long as you retain this notice you can
# do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return
# Danijel Tasov
# ----------------------------------------------------------------------

use 5.016;
use open ':locale';
use strict;
use Mojo::UserAgent;
use Data::Dumper::Concise;
use Digest::SHA;
use XML::Feed;
use Devel::Peek;
#use Carp::Always;
use URI;
use Encode;
use DBI;
use utf8;
use feature 'unicode_strings';

my $db = DBI->connect(
  "dbi:SQLite:/home/danielt/log/polizei2.db",
  undef,
  undef,
  { RaiseError => 1, PrintError => 0 }) or die($DBI::errstr);

my $insert = $db->prepare(q{
    insert into meldungen_idx
    (id, ts, meldung_docid) values (?,datetime('now'), ?)
});
my $docins = $db->prepare(q{
    insert into meldungen_fts (meldung, title) values (?,?)
});
my $feed = "https://www.polizei.bayern.de/muenchen/polizei.rss";
my $myfeed = XML::Feed->new( 'RSS' );
$myfeed->title("Polizei München Presseberichte" );
$myfeed->link("http://www.polizei.bayern.de/muenchen/news/presse/aktuell/index.html");

my $c = Mojo::UserAgent->new;

$c->max_redirects(2)->get($feed)->res->dom->find("item link")->each(sub{
    buildItems($_->text);
});

print Encode::encode('utf-8', $myfeed->as_xml);

sub buildItems {
    my $link = shift;
    my $stop = shift;
    my $dom = $c->max_redirects(2)->get($link)->res->dom;
    unless($stop) {
        for my $l ($dom->find('a[class="verweiseLinks"]')->each) {
            if ($l->text =~ /Wiesn.*(?:Report|Bericht)/i) {
                buildItems(URI->new_abs($l->attr("href"),$link)->as_string,1);
            }
        }
    }

    $dom->find("img")->each(sub {
        my $img = shift;
        my $src = $img->attr('src');
        my $newsrc = URI->new_abs($src, $link)->as_string;
        $img->attr(src => $newsrc);
    });

    my @titles = map { $_->text } $dom->find("div.inhaltUeberschriftFolgeseiten2")->each;
    my @contents = map { $_->content } $dom->find("div.inhaltText")->each;


    if(@titles != @contents) {
        warn("Ooops: number of titles != number of contents");
        return;
    }

    for my $i (0..$#titles) {
        #Dump($contents[$i]);
        my $guid = Digest::SHA::sha1_hex(Encode::encode('utf-8', $contents[$i]));
        #$contents[$i] = Encode::encode('utf-8', $contents[$i]);
        #say STDERR "|$contents[$i]|\n\n";
        my $item = XML::Feed::Entry->new('RSS');
        next unless (length($titles[$i]) or length($contents[$i]));
        $contents[$i] =~ s/\x01//g;
        $item->title($titles[$i]);
        $item->content($contents[$i]);
        $item->link('https://data.rbfh.de/p.cgi/'.substr($guid, 0, 10));
        $item->id($guid);
        $myfeed->add_entry( $item );

        eval {
            $db->begin_work;
            $docins->execute($contents[$i], $titles[$i]);
            my $docid = $db->sqlite_last_insert_rowid;
            $insert->execute($guid, $docid);
        };
        my $err = $@;
        unless($err) {
            $db->commit;
            next;
        }
        say $err if $err !~ /DBD::SQLite::st execute failed: UNIQUE constraint failed:/;
        $db->rollback;
    }


}

