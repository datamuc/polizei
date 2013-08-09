#!/opt/perl/perls/perl-5.14.0/bin/perl

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
{
    my $hinweis = XML::Feed::Entry->new('RSS');
    $hinweis->title("Hinweis in eigener Sache");
    $hinweis->content(q{<p>
        Die einzelnen Meldungen werden jetzt in einer SQLite-Datenbank
        gespeichert. Außerdem gibt es jetzt eine kleine Webapp mit der man
        auf die einzelnen Meldungen zugreifen kann.

        <p>Im Feed ist das alles auch schon richtig verlinkt.

        <p>Wenn man jemanden auf eine Meldung hinweisen will, muss
        man also nicht mehr den Link <blockquote>http://www.polizei.bayern.de/muenchen/news/presse/aktuell/index.html/183424</blockquote> mit dem Hinweis "1218" verschicken, sondern kann einfach folgenden Link verteilen: <blockquote><a href="http://data.rbfh.de/p.cgi/bb9978ebbfe4dbbd19b8dce8c0787597c0d91ad6">http://data.rbfh.de/p.cgi/bb9978ebbfe4dbbd19b8dce8c0787597c0d91ad6</a></blockquote>
    });
    $hinweis->id('0ebf27a9-47c3-46d2-88ee-fa005f257fc0');
    $hinweis->link('http://data.rbfh.de/p.cgi/'.$hinweis->id);
    $myfeed->add_entry($hinweis);
    $insert->execute($hinweis->id, $hinweis->title, $hinweis->content->body);
}
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

