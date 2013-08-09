#!/opt/perl/perls/perl-5.16.3/bin/perl

package Polizei {
    use Web::Simple;
    use DBI;
    use Template::Mustache;
    use Data::Section::Simple;

    my $db = DBI->connect("dbi:SQLite:/home/danielt/log/polizei.db");
    my $ds = Data::Section::Simple->new('main');
    my $get = $db->prepare("select * from meldungen where id = ?");
    my $page = $db->prepare("select id,title from meldungen order by ts desc limit 10 offset 10 * ?");

    my $partials = { head => scalar $ds->get_data_section('head') };
    my $index = $ds->get_data_section('index');
    my $meldung = $ds->get_data_section('meldung');

    sub dispatch_request {
        my ($self, $env) = @_;
        sub ((GET|HEAD) + /) {
            my ($self) = @_;
            $self->render_page(0, $env);
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

    sub render_article {
        my ($self, $id, $env) = @_;
        $get->execute($id);
        my $row = $get->fetchrow_hashref;

        unless($row) {
            return $self->render_404;
        }

        $row->{script_name} = $env->{SCRIPT_NAME};

        [ 200,
            ['Content-Type', 'text/html; charset=utf-8'],
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
            $m->{link} = "$env->{SCRIPT_NAME}/$m->{id}";
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
            ['content-type', 'text/plain'],
            [ '404 Not Found' ]
        ]
    }

}

package main;
Polizei->run_if_script;

__DATA__
@@ index
{{>head}}
<h2><a href="/polizei.rss">Polizei München Presseberichte</a></h2>
<ul>
{{#meldungen}}
<li><a href="{{link}}">{{title}}</a>
{{/meldungen}}
</ul>
<hr>
<a href="{{next}}">weiter…</a>

@@ meldung
{{>head}}
<h2><a href="{{script_name}}/">Polizei München Presseberichte</a></h2>
<h3>{{title}}</h3> {{{meldung}}}

@@ head
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
    "http://www.w3.org/TR/html4/loose.dtd">
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
    font-family: "Linux Libertine O", Georgia, "DejaVu Serif", "Times New Roman", sans-serif;
    padding-bottom: 25%;
}
a { color: #2c2; text-decoration: none; }
a:visited { color: #0a0; }
</style>
<link rel="alternate" type="application/rss+xml" title="Pressemeldungen der Polizei München" href="/polizei.rss">
