use lib 't/04-nativecall';
use CompileTestLib;
use lib 'lib';
use NativeCall;
use Test;

plan 10;

compile_test_lib('04-pointers');

sub ReturnSomePointer()         returns Pointer is native("./04-pointers") { * }
sub CompareSomePointer(Pointer) returns int32   is native("./04-pointers") { * }

my $x     = ReturnSomePointer();
my int $a = 4321;

ok CompareSomePointer($x), 'Got passed back the pointer I returned';
ok $x,     'Non-NULL pointer is trueish';
ok $x.Int, 'Calling .Int on non-NULL pointer is trueish';
ok +$x,    'Calling prefix:<+> on non-NULL pointer is trueish';
is +$x.perl.EVAL,          +$x,               'Pointer roundtrips okay using .perl and EVAL';
is Pointer.new.gist,       'Pointer<NULL>',   'Pointer.new gistifies to "Pointer<NULL>"';
is Pointer.new(0).gist,    'Pointer<NULL>',   'Pointer.new(0) gistifies to "Pointer<NULL>"';
is Pointer.new(1234).gist, 'Pointer<0x4d2>',  'Pointer.new(1234) gistifies to "Pointer<0x4d2>"';
is Pointer.new($a).gist,   'Pointer<0x10e1>', 'Pointer.new accepts a native int too';
is Pointer.gist,           '(Pointer)',       'The Pointer type object gistifies ot "Pointer"';
