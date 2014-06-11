use inc::Module::Install;

version_from ('lib/RT/Extension/JSGantt.pm');
RTx('RT-Extension-JSGantt');

author ('sunnavy <sunnavy@bestpractical.com>');
abstract_from('lib/RT/Extension/JSGantt.pm');
readme_from('lib/RT/Extension/JSGantt.pm');
license('GPLv2');

repository 'git://github.com/bestpractical/rt-extension-jsgantt.git';

requires( 'JSON' );
requires( 'List::MoreUtils' );

requires_rt('4.0.0');

&WriteAll;
