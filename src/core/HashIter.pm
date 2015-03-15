my class HashIter is Iterator {
    has $!reified;             # Parcel we return after reifying
    has Mu $!hashiter;         # the VM level hash iterator
    has Mu $!keystore;         # key store, if it's a typed hash
    has int $!mode;            # pair = 0, kv = 1, k = 2, v = 3, invert = 4

    method new($hash, :$keystore, :$pairs, :$kv, :$k, :$v, :$anti, :$invert) {
        nqp::create(self).BUILD($hash, $keystore,
            $pairs  ?? 0 !!
            $kv     ?? 1 !!
            $k      ?? 2 !!
            $v      ?? 3 !!
            $anti   ?? 4 !!
            $invert ?? 5 !!
                       0);
    }
    method pairs($h,$keystore?)     { nqp::create(self).BUILD($h,$keystore,0) }
    method kv($h,$keystore?)        { nqp::create(self).BUILD($h,$keystore,1) }
    method keys($h,$keystore?)      { nqp::create(self).BUILD($h,$keystore,2) }
    method values($h,$keystore?)    { nqp::create(self).BUILD($h,$keystore,3) }
    method antipairs($h,$keystore?) { nqp::create(self).BUILD($h,$keystore,4) }
    method invert($h,$keystore?)    { nqp::create(self).BUILD($h,$keystore,5) }

    submethod BUILD($hash, $keystore, Int $mode) {
        $!hashiter :=
          nqp::iterator(nqp::getattr(nqp::decont($hash), EnumMap, '$!storage'));
        $!mode      = $mode;
        $!keystore := nqp::getattr(nqp::decont($keystore), EnumMap, '$!storage')
          if $keystore.DEFINITE;
        self;
    }

    method reify($n, :$sink) {  # hashes are finite, and hashiter non-reentrant, so do eager snapshot for now
        unless nqp::isconcrete($!reified) {
            my int $mode  =  $!mode;
            my Mu $rpa    := nqp::list();
            my $it        := $!hashiter;

            my Mu $pairish;
            if $mode == 0 {   # :pairs
                if nqp::defined($!keystore) {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, Pair.new(
                            :key(nqp::atkey($!keystore, nqp::iterkey_s($pairish))),
                            :value(nqp::hllize(nqp::iterval($pairish)))));
                    }
                }
                else {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, Pair.new(
                            :key(nqp::p6box_s(nqp::iterkey_s($pairish))),
                            :value(nqp::hllize(nqp::iterval($pairish)))));
                    }
                }
            }
            elsif $mode == 1 {  # :kv
                if nqp::defined($!keystore) {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, nqp::atkey($!keystore, nqp::iterkey_s($pairish)).item);
                        nqp::push($rpa, nqp::hllize(nqp::iterval($pairish)).item);
                    }
                }
                else {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, nqp::p6box_s(nqp::iterkey_s($pairish)));
                        nqp::push($rpa, nqp::hllize(nqp::iterval($pairish)).item);
                    }
                }
            }
            elsif $mode == 2 {  # :k
                if nqp::defined($!keystore) {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, nqp::atkey($!keystore, nqp::iterkey_s($pairish)).item);
                    }
                }
                else {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, nqp::p6box_s(nqp::iterkey_s($pairish)));
                    }
                }
            }
            elsif $mode == 3 {  # :v
                while $it {
                    $pairish := nqp::shift($it);
                    nqp::push($rpa, nqp::hllize(nqp::iterval($pairish)).item);
                }
            }
            elsif $mode == 4 {  # :anti
                if nqp::defined($!keystore) {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, Pair.new(
                            :value(nqp::atkey($!keystore, nqp::iterkey_s($pairish))),
                            :key(nqp::hllize(nqp::iterval($pairish)))));
                    }
                }
                else {
                    while $it {
                        $pairish := nqp::shift($it);
                        nqp::push($rpa, Pair.new(
                            :value(nqp::p6box_s(nqp::iterkey_s($pairish))),
                            :key(nqp::hllize(nqp::iterval($pairish)))));
                    }
                }
            }
            elsif $mode == 5 {  # :invert
                if nqp::defined($!keystore) {
                    while $it {
                        $pairish := nqp::shift($it);
                        my $k := nqp::atkey($!keystore, nqp::iterkey_s($pairish));
                        nqp::push($rpa, Pair.new(
                            :value($k),
                            :key($_)))
                                for nqp::hllize(nqp::iterval($pairish)).list;
                    }
                }
                else {
                    while $it {
                        $pairish := nqp::shift($it);
                        my $k := nqp::p6box_s(nqp::iterkey_s($pairish));
                        nqp::push($rpa, Pair.new(
                            :value($k),
                            :key($_)))
                                for nqp::hllize(nqp::iterval($pairish)).list;
                    }
                }
            }
            else {
                die "Unknown hash iteration mode: $mode";
            }

            if $it {
                my $nextiter := nqp::create(self);
                nqp::bindattr($nextiter, HashIter, '$!hashiter', $it);
                nqp::bindattr($nextiter, HashIter, '$!keystore', $!keystore);
                nqp::bindattr_i($nextiter, HashIter, '$!mode', $mode);
                nqp::push($rpa, $nextiter);
            }

            $!reified := nqp::p6parcel($rpa, nqp::null());
            # release references to objects we no longer need/own
            $!hashiter := Any;
        }
        $!reified;
    }

    multi method infinite(HashIter:D:) { False }

    multi method DUMP(HashIter:D: :$indent-step = 4, :%ctx?) {
        return DUMP(self, :$indent-step) unless %ctx;

        my Mu $attrs := nqp::list();
        nqp::push($attrs, '$!reified'  );
        nqp::push($attrs,  $!reified   );
        nqp::push($attrs, '$!hashiter' );
        nqp::push($attrs,  $!hashiter  );
        nqp::push($attrs, '$!keystore' );
        nqp::push($attrs,  $!keystore  );
        nqp::push($attrs, '$!mode'     );
        nqp::push($attrs,  $!mode      );
        self.DUMP-OBJECT-ATTRS($attrs, :$indent-step, :%ctx);
    }
}

# vim: ft=perl6 expandtab sw=4
