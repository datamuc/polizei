#!/opt/perl/perls/perl-5.22.0/bin/perl

# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <m@rbfh.de> wrote this file. As long as you retain this notice you can
# do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return
# Danijel Tasov
# ----------------------------------------------------------------------

use 5.010;
BEGIN {
    use POSIX;
    POSIX::setlocale(&POSIX::LC_ALL, "de_DE.UTF-8");
};


package Polizei {
    use Web::Simple;
    use DBI;
    use Text::Hogan::Compiler;
    use Data::Section::Simple;
    use Time::Piece;
    use IO::File;
    use Plack::Middleware::Deflater;
    use JSON;
    Time::Piece::mon_list(qw(
        Januar Februar März April Mai Juni
        Juli August September Oktober November Dezember
    ));

    my $db = DBI->connect("dbi:SQLite:/home/danielt/log/polizei2.db");
    my $ds = Data::Section::Simple->new('main');
    my $get = $db->prepare(q{
        select *,strftime('%s', ts) epoch
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.rowid)
        where id like ? || '%'
    });
    my $page = $db->prepare(q{
        select id,title
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.rowid)
        order by ts desc limit 10 offset 10 * ?
    });
    my $search = $db->prepare(q{
        select id,title,snippet(meldungen_fts) snip
        from meldungen_idx i join meldungen_fts f on (i.meldung_docid = f.rowid)
        where meldungen_fts match ?
        order by ts desc
        limit 200
    });

    my $partials = { head => Text::Hogan::Compiler->compile(scalar $ds->get_data_section('head')) };
    my $index = $ds->get_data_section('index');
    my $meldung = $ds->get_data_section('meldung');
    my $nothing = $ds->get_data_section('nothing');

    sub dispatch_request {
        my ($self, $env) = @_;
        '/api/...' => sub {
            '' => sub { response_filter {
                [ $_[0]->[0] ,
                  ['Content-Type' => 'application/json'],
                  [JSON->new->encode($_[0]->[1])]
                ]
            }},
            '(GET|HEAD) + /page/*' => sub {
                my ($self, $id) = @_;
                $self->json_page($id, $env);
            },
            '(GET|HEAD) + /id/*' => sub {
                my ($self, $id) = @_;
                $self->json_article($id, $env);
            },
        },
        '(GET|HEAD) + /' => sub {
            my ($self) = @_;
            $self->render_page(0, $env);
        },
        '(GET|HEAD) + /search/ + ?needle=' => sub {
            my ($self, $needle) = @_;
            $self->render_search($needle,$env);
        },
        '(GET|HEAD) + /p/*'  => sub {
            my ($self, $id) = @_;
            $self->render_page($id, $env);
        },
        '(GET|HEAD) + /*' =>  sub {
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
        my $t = Text::Hogan::Compiler->new->compile($index);
        [ 200,
          [ 'content-type', 'text/html' ],
          [ $t->render($vars, $partials) ]
        ];
    }

    sub render_nothing_found {
        my $vars = {
            script_name => $_[1]->{SCRIPT_NAME},
            needle => $_[2],
        };
        my $t = Text::Hogan::Compiler->new->compile($nothing);
        [ 200,
          [ 'content-type', 'text/html'],
          [ $t->render($vars, $partials) ]
        ];
    }

    sub json_article {
        my ($self, $id, $env) = @_;
        $get->execute($id);
        my $row = $get->fetchrow_hashref;

        unless($row) {
            return [404, {}]
        }

        if($get->fetchrow_hashref) {
            # there is more than one row? -> 404
            return [404, {}]
        }

        my $tp = localtime($row->{epoch});
        $row->{datetime} = gmtime($row->{epoch})->datetime."Z";
        $row->{datum} = sprintf "%d. %s %d",
            $tp->mday, $tp->month, $tp->year;

        [ 200, $row ]
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
            $tp->mday, $tp->month, $tp->year;

        my $t = Text::Hogan::Compiler->new->compile($meldung);
        [ 200,
            ['Content-Type', 'text/html'],
            [ $t->render($row, $partials) ]
        ];
    }

    sub json_page {
        my ($self, $id, $env) = @_;
        $page->execute(int($id));
        my $meldungen = $page->fetchall_arrayref({});
        unless(@$meldungen) {
            return [404, []]
        }
        for my $m (@$meldungen) {
            $m->{shortid} = substr($m->{id}, 0, 10);
            $m->{title} = "[no title]"
                unless(length($m->{title}));
        }
        return [200, $meldungen];
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
        my $t = Text::Hogan::Compiler->new->compile($index);
        [ 200,
          [ 'content-type', 'text/html;'],
          [ $t->render($vars, $partials) ]
        ];
    }

    sub render_404 {
        [ 404,
            ['content-type', 'text/html'],
            IO::File->new("/home/danielt/public_html/404.html")
        ]
    }

    around 'to_psgi_app', sub {
      use Plack::Builder;
      my ($orig, $self) = @_;
      my $app = $self->$orig(@_);
      builder {
#	enable "Deflater",
#            content_type => ['text/css','text/html','text/javascript','application/javascript'],
#	    vary_user_agent => 1;
        $app;
      };
    };

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
<div id="meldung">{{{meldung}}}</div>

@@ nothing
{{>head}}
Nothing found

@@ head
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="//data.rbfh.de/pure-0.6.0/pure-min.css">
<link rel="stylesheet" href="/fonts/noto/style.css">
<link rel="stylesheet" href="/fonts/lm/style.css">

{{#title}}
<title>{{title}} - Polizeiberichte München</title>
{{/title}}
{{^title}}
<title>Polizeiberichte München</title>
{{/title}}
<style type="text/css">
body {
    /* text-rendering: optimizeLegibility; */
    /* font-variant-ligatures: common-ligatures; */
    line-height: 1.6;
    margin-left: auto;
    margin-right: auto;
    font-family: "Noto Serif", serif;
    font-size: 12pt;
    padding-bottom: 25%;
    padding-left: 4vw;
    padding-right: 4vw;
}
@media screen {
    body {
        max-width: 35em;
        font-size: 13pt;
        background-color: #000;
        color: #bbb;
    }
    a { color: rgb(0,141,201); text-decoration: none; }
    a:visited { color: rgb(0,101,161); }
    h2 a:visited { color: rgb(0,141,201); }
    .button-small { font-size: 75%; background-color: rgb(0,141,201); }
    a.button-small { color: #fff; }
}
#meldung { hyphens: auto; }
h1,h2,h3,h4,h5,h6 { font-family: "Latin Modern Sans", sans-serif; font-weight: bold; }
@media print {
  .pure-form { display: none; }
}
</style>
<link rel="alternate" type="application/rss+xml" title="Pressemeldungen der Polizei München" href="/polizei.rss">
</head>
<form accept-charset="UTF-8" method="GET" class="pure-form" action="{{script_name}}/search/">
<input class="pure-input-rounded" placeholder="suche..." id="search" value="{{needle}}" name="needle" /> <a class="pure-button button-small" href="https://www.sqlite.org/fts3.html#section_3">?</a>
</form>
