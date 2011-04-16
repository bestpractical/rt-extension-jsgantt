use inc::Module::Install;

RTx('RT-Extension-JSGantt');
author ('sunnavy <sunnavy@bestpractical.com>');
version_from ('lib/RT/Extension/JSGantt.pm');
abstract_from('lib/RT/Extension/JSGantt.pm');
license('GPLv2');
repository 'git://github.com/bestpractical/rt-extension-jsgantt.git';

requires( 'JSON' );

&WriteAll;
