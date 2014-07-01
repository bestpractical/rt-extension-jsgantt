use inc::Module::Install;

RTx('RT-Extension-JSGantt');
license('GPLv2');

repository 'http://github.com/bestpractical/rt-extension-jsgantt';

requires( 'JSON' );
requires( 'List::MoreUtils' );

requires_rt('4.0.0');

&WriteAll;
