#!/opt/perl/perls/perl-5.16.3/bin/perl

# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <m@rbfh.de> wrote this file. As long as you retain this notice you can
# do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return
# Danijel Tasov
# ----------------------------------------------------------------------

use 5.010;

package Polizei {
    use Web::Simple;
    use DBI;
    use Template::Mustache;
    use Data::Section::Simple;
    use Time::Piece;
    use IO::File;
    Time::Piece::mon_list(qw(
        Januar Februar März April Mai Juni
        Juli August September Oktober November Dezember
    ));

    my $db = DBI->connect("dbi:SQLite:/home/danielt/log/polizei2.db");
    my $ds = Data::Section::Simple->new('main');
    my $get = $db->prepare(q{
        select *,strftime('%s', ts) epoch
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.docid)
        where id like ? || '%'
    });
    my $page = $db->prepare(q{
        select id,title
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.docid)
        order by ts desc limit 10 offset 10 * ?
    });
    my $search = $db->prepare(q{
        select id,title,snippet(meldungen_fts) snip
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.docid)
        where meldungen_fts match ?
        order by ts desc
        limit 200
    });

    my $partials = { head => scalar $ds->get_data_section('head') };
    my $index = $ds->get_data_section('index');
    my $meldung = $ds->get_data_section('meldung');
    my $nothing = $ds->get_data_section('nothing');

    sub dispatch_request {
        my ($self, $env) = @_;
        sub ((GET|HEAD) + /) {
            my ($self) = @_;
            $self->render_page(0, $env);
        },
        sub ((GET|HEAD) + /search/ + ?needle=) {
            my ($self, $needle) = @_;
            $self->render_search($needle,$env);
        },
        sub ((GET|HEAD) + /p/*) {
            my ($self, $id) = @_;
            $self->render_page($id, $env);
        },
        sub ((GET|HEAD) + /*) {
            my ($self, $id) = @_;
            $self->render_article($id,$env);
        }
    }

    sub render_search {
        my ($self, $needle, $env) = @_;
        $search->execute($needle);
        my $meldungen = $search->fetchall_arrayref({});
        unless(@$meldungen) {
            return $self->render_nothing_found($env, $needle);
        }
        for my $m (@$meldungen) {
            $m->{link} = "$env->{SCRIPT_NAME}/". substr($m->{id}, 0, 10);
            $m->{title} = "[no title]"
                unless(length($m->{title}));
        }
        my $vars = {
            meldungen => $meldungen,
            script_name => $env->{SCRIPT_NAME},
            needle => $needle,
        };
        [ 200,
          [ 'content-type', 'text/html; charset=utf-8'],
          [ Template::Mustache->render($index, $vars, $partials)]
        ];
    }

    sub render_nothing_found {
        my $vars = {
            script_name => $_[1]->{SCRIPT_NAME},
            needle => $_[2],
        };
        [ 200,
          [ 'content-type', 'text/html; charset=utf-8'],
          [ Template::Mustache->render($nothing, $vars, $partials)]
        ];
    }

    sub render_article {
        my ($self, $id, $env) = @_;
        $get->execute($id);
        my $row = $get->fetchrow_hashref;

        unless($row) {
            return $self->render_404;
        }

        if($get->fetchrow_hashref) {
            # there is more than one row? -> 404
            return $self->render_404;
        }

        $row->{script_name} = $env->{SCRIPT_NAME};

        my $tp = localtime($row->{epoch});
        $row->{datum} = sprintf "%d. %s %d",
            $tp->mday, $tp->fullmonth, $tp->year;

        [ 200,
            ['Content-Type', 'text/html'],
            [ Template::Mustache->render($meldung, $row, $partials) ]
        ];
    }

    sub render_page {
        my ($self, $id, $env) = @_;

        $page->execute(int($id));
        my $meldungen = $page->fetchall_arrayref({});
        unless(@$meldungen) {
            return $self->render_404;
        }
        for my $m (@$meldungen) {
            $m->{link} = "$env->{SCRIPT_NAME}/". substr($m->{id}, 0, 10);
            $m->{title} = "[no title]"
                unless(length($m->{title}));
        }
        my $weiter = "$env->{SCRIPT_NAME}/p/" . ($id + 1);
        my $vars = {
            meldungen => $meldungen,
            next => $weiter,
            script_name => $env->{SCRIPT_NAME},
        };
        [ 200,
          [ 'content-type', 'text/html; charset=utf-8'],
          [ Template::Mustache->render($index, $vars, $partials)]
        ];
    }

    sub render_404 {
        [ 404,
            ['content-type', 'text/html'],
            IO::File->new("/home/danielt/public_html/404.html")
        ]
    }

}

package main;
Polizei->run_if_script;

__DATA__
@@ index
{{>head}}
{{#needle}}
<h2><a href="{{script_name}}/">Polizei München Presseberichte</a></h2>
{{/needle}}
{{^needle}}
<h2><a href="/polizei.rss">Polizei München Presseberichte</a></h2>
{{/needle}}
<ul>
{{#meldungen}}
<li><a href="{{link}}">{{title}}</a>{{#snip}}
<br />{{{snip}}}{{/snip}}
{{/meldungen}}
</ul>
<hr>
{{#next}}
<a href="{{next}}">weiter…</a>
{{/next}}

@@ meldung
{{>head}}
<h2><a href="{{script_name}}/">Polizei München Presseberichte</a></h2>
<h3>{{title}}</h3>
<p style="text-align: right">{{ datum }}</p>
{{{meldung}}}

@@ nothing
{{>head}}
Nothing found

@@ head
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
    "http://www.w3.org/TR/html4/loose.dtd">
<meta http-equiv="content-type" content="text/html; charset=UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="//data.rbfh.de/pure-0.5.0/pure-min.css">
{{#title}}
<title>{{title}} - Polizeiberichte München</title>
{{/title}}
{{^title}}
<title>Polizeiberichte München</title>
{{/title}}
<style type="text/css">
body {
    max-width: 30em;
    background-color: #222;
    color: #bbb;
    line-height: 1.5;
    margin-left: auto;
    margin-right: auto;
    font-size: 15pt;
    font-family: Tinos, "Linux Libertine O", Georgia, "DejaVu Serif", "Times New Roman", sans-serif;
    padding-bottom: 25%;
}
a { color: #2c2; text-decoration: none; }
a:visited { color: #0a0; }
.button-small { font-size: 75%; background-color: #2c2; }
a.button-small { color: #fff; }
</style>
<link rel="alternate" type="application/rss+xml" title="Pressemeldungen der Polizei München" href="/polizei.rss">
<form method="GET" class="pure-form" action="{{script_name}}/search/">
<input class="pure-input-rounded" placeholder="suche..." id="search" value="{{needle}}" name="needle" /> <a class="pure-button button-small" href="https://www.sqlite.org/fts3.html#section_3">?</a>
</form>
