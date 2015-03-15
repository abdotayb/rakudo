
sub METAOP_ASSIGN(\op) {
    -> Mu \a, Mu \b { a = op.( a // op.(), b) }
}

sub METAOP_TEST_ASSIGN:<//>(\lhs, $rhs) is rw { lhs // (lhs = $rhs()) }
sub METAOP_TEST_ASSIGN:<||>(\lhs, $rhs) is rw { lhs || (lhs = $rhs()) }
sub METAOP_TEST_ASSIGN:<&&>(\lhs, $rhs) is rw { lhs && (lhs = $rhs()) }

sub METAOP_NEGATE(\op) {
    -> Mu \a, Mu \b { !op.(a ,b) }
}

sub METAOP_REVERSE(\op) {
    -> Mu \a, Mu \b { op.(b, a) }
}

sub METAOP_CROSS(\op, &reduce) {
    return &infix:<X> if op === &infix:<,>;

    -> |lol {
        my $rop = lol.elems == 2 ?? op !! &reduce(op);
        my $Inf = False;
        my @lol = eager for ^lol.elems -> $i {
            my \elem = lol[$i];         # can't use mapping here, mustn't flatten
            $Inf = True if elem.infinite;

            if nqp::iscont(elem) { (elem,).list.item }
            else                 { (elem,).flat.item }
        }
        my Mu $cache := nqp::list();
        my int $i = 0;
        for ^lol.elems {
            $i = $_;
            my Mu $rpa := nqp::list();
            nqp::bindpos($cache, $i, $rpa);
        }
        my int $n = lol.elems - 1;
        my $j = 0;
        my @j;
        my @v;

        # Don't care if a finite Range is lazy
        my $policy = &list;
        if nqp::istype(lol[0],Range) {
            $policy = &EAGER unless $Inf || lol[0].infinite;
        }

        $i = 0;
        $policy(gather {
            while $i >= 0 {
                my Mu $sublist := nqp::atpos($cache, $i);
                if $j < nqp::elems($sublist) {
                    my Mu $o := nqp::atpos($sublist, $j);
                    @v[$i] := $o;
                    $j = $j + 1;
                    if $i >= $n { take $rop(|@v); }
                    else { $i = $i + 1; @j.push($j); $j = 0; }
                }
                elsif @lol[$i].gimme(1) {
                    my Mu $o := @lol[$i].shift;
                    nqp::bindpos($sublist, $j, $o);
                    redo;
                }
                else {
                    $i = $i - 1;
                    if $i { $j = @j.pop if $i > 0 }  # continue previous dimension where we left off
                    else  {
                        $j = 0;
                        my Mu $sublist := nqp::atpos($cache,$i);
                        nqp::pop($sublist);          # don't cache 1st dimension (could be infinite)
                    }
                }
            }
        })
    }
}

sub METAOP_ZIP(\op, &reduce) {
    -> |lol {
        my $arity = lol.elems;
        my $rop = $arity == 2 ?? op !! &reduce(op);
        my @lol = eager for ^lol.elems -> $i {
            my \elem = lol[$i];         # can't use mapping here, mustn't flatten

            if nqp::iscont(elem) { (elem,).list.item }
            else                 { (elem,).flat.item }
        }
        gather {
            loop {
                my \z = @lol.map: { last unless .gimme(1); .shift }
                last if z.elems < $arity;
                take-rw $rop(|z);
            }
        }
    }
}

sub METAOP_REDUCE_LEFT(\op, :$triangle) {
    my $x := $triangle ??
        (sub (*@values) {
            return () unless @values.gimme(1);
            GATHER({
                my $result := @values.shift;
                take $result;
                take ($result := op.($result, @values.shift))
                    while @values.gimme(1);
            }, :infinite(@values.infinite))
        }) !!
        (sub (*@values) {
            return op.() unless @values.gimme(1);
            my $result := @values.shift;
            return op.($result) unless @values.gimme(1);
            my int $i;
            while my int $c = @values.gimme(1000) {
                $i = 0;
                $result := op.($result, @values.shift)
                    while ($i = $i + 1) <= $c;
            }
            $result;
        })
}

sub METAOP_REDUCE_RIGHT(\op, :$triangle) {
    my $x :=
    sub (*@values) {
        my $list = @values.reverse;
        if $triangle {
            return () unless $list.gimme(1);
            gather {
                my $result := $list.shift;
                take $result;
                take ($result := op.($list.shift, $result))
                    while $list.gimme(1);
            }
        }
        else {
            return op.() unless $list.gimme(1);
            my $result := $list.shift;
            return op.($result) unless $list.gimme(1);
            my int $i;
            while my int $c = $list.gimme(1000) {
                $i = 0;
                $result := op.($list.shift, $result)
                    while ($i = $i + 1) <= $c;
            }
            $result;
        }
    }
}


sub METAOP_REDUCE_LIST(\op, :$triangle) {
    $triangle
        ??  sub (*@values) {
                return () unless @values.gimme(1);
                GATHER({
                    my @list;
                    while @values {
                        @list.push(@values.shift);
                        take op.(|@list);
                    }
                }, :infinite(@values.infinite))
            }
        !!  sub (*@values) { op.(|@values) }
}


sub METAOP_REDUCE_LISTINFIX(\op, :$triangle) {
    $triangle
        ??  sub (|values) {
                my \p = values[0];
                return () unless p.elems;
                my int $i = 0;
                GATHER({
                    my @list;
                    while $i < p.elems {
                        @list.push(p[$i]);
                        $i = $i + 1;
                        take op.(|@list);
                    }
                }, :infinite(p.infinite))
            }
        !!  sub (|values) { my \p = values[0]; op.(|p) }
}


sub METAOP_REDUCE_CHAIN(\op, :$triangle) {
    $triangle
        ??  sub (*@values) {
                my $state = True;
                my Mu $current = @values.shift;
                gather {
                    take $state;
                    while $state && @values.gimme(1) {
                        $state = op.($current, @values[0]);
                        take $state;
                        $current = @values.shift;
                    }
                    take False for @values;
                }

            }
        !! sub (*@values) {
                my $state = True;
                my Mu $current = @values.shift;
                while @values.gimme(1) {
                    $state = op.($current, @values[0]);
                    $current = @values.shift;
                    return $state unless $state;
                }
                $state;
            }
}


sub METAOP_REDUCE_XOR(\op, :$triangle) {
    X::NYI.new(feature => 'xor reduce').throw;
}

sub METAOP_HYPER(\op, *%opt) {
    -> Mu \a, Mu \b { hyper(op, a, b, |%opt) }
}

proto sub METAOP_HYPER_POSTFIX(|) {*}
multi sub METAOP_HYPER_POSTFIX(\obj, \op) { flatmap(op, obj) }
multi sub METAOP_HYPER_POSTFIX(\obj, \args, \op) { flatmap( -> \o { op.(o,|args) }, obj ) }

sub METAOP_HYPER_PREFIX(\op, \obj) { deepmap(op, obj) }

sub METAOP_HYPER_CALL(\list, |args) { deepmap(-> $c { $c(|args) }, list) }

proto sub hyper(|) { * }

multi sub hyper(&op, \left, \right, :$dwim-left, :$dwim-right) {
    op(left, right);
}

# XXX Should really be Iterable:D by spec, but then it doesn't work with Parcel
multi sub hyper(&operator, Positional:D \left, \right, :$dwim-left, :$dwim-right) {
    my @result;
    X::HyperOp::Infinite.new(:side<left>, :&operator).throw if left.infinite;
    my int $elems = left.elems;
    X::HyperOp::NonDWIM.new(:&operator, :left-elems($elems), :right-elems(1)).throw
        unless $elems == 1 or $elems > 1 and $dwim-right or $elems == 0 and $dwim-left || $dwim-right;
    my @left := left.eager;
    for ^$elems {
        @result[$_] := hyper(&operator, @left[$_], right, :$dwim-left, :$dwim-right);
    }
    # Coerce to the original type
    my $type = left.WHAT;
    nqp::iscont(left) ?? $type(@result.eager).item !! $type(@result.eager)
}

multi sub hyper(&operator, \left, Positional:D \right, :$dwim-left, :$dwim-right) {
    my @result;
    X::HyperOp::Infinite.new(:side<right>, :&operator).throw if right.infinite;
    my int $elems = right.elems;
    X::HyperOp::NonDWIM.new(:&operator, :left-elems(1), :right-elems($elems)).throw
        unless $elems == 1 or $elems > 1 and $dwim-left or $elems == 0 and $dwim-left || $dwim-right;
    my @right := right.eager;
    for ^$elems {
        @result[$_] := hyper(&operator, left, @right[$_], :$dwim-left, :$dwim-right);
    }
    # Coerce to the original type
    my $type = right.WHAT;
    nqp::iscont(right) ?? $type(@result.eager).item !! $type(@result.eager)
}

multi sub hyper(&operator, Positional:D \left, Positional:D \right, :$dwim-left, :$dwim-right) {
    my @result;

    # Check if a dwimmy side ends *. If so, that's considered a replication of the final element
    my $left-elems  = left.elems;
    my $right-elems = right.elems;
    my $left-whatev = 0;
    my $right-whatev = 0;
    if $dwim-left and 1 < $left-elems < Inf and left[$left-elems - 1] ~~ Whatever {
        $left-whatev++; $left-elems--;
    }
    if $dwim-right and 1 < $right-elems < Inf and right[$right-elems - 1] ~~ Whatever {
        $right-whatev++; $right-elems--;
    }

    # Determine the number of elements we need, and how many we non-dwimmily have
    my int $max-elems;
    my int $min-elems;
    if $left-elems == $right-elems {
        X::HyperOp::Infinite.new(:side<both>, :&operator).throw
            if $left-elems == Inf;
        $max-elems = $min-elems = $left-elems;
    }
    elsif $dwim-left && $dwim-right {
        X::HyperOp::Infinite.new(:side($left-elems == Inf ?? "left" !! "right"), :&operator).throw
            if $left-elems | $right-elems == Inf;
        $max-elems = $left-elems max $right-elems;
        $min-elems = $left-elems min $right-elems;
    }
    elsif $dwim-left {
        X::HyperOp::Infinite.new(:side<right>, :&operator).throw
            if $right-elems == Inf;
        $max-elems = $right-elems;
        $min-elems = $left-elems min $right-elems; # could be truncation
    }
    elsif $dwim-right {
        X::HyperOp::Infinite.new(:side<left>, :&operator).throw
            if $left-elems == Inf;
        $max-elems = $left-elems;
        $min-elems = $left-elems min $right-elems; # could be truncation
    }
    else {
        X::HyperOp::NonDWIM.new(:&operator, :$left-elems, :$right-elems).throw
    }

    # Generate all of the non-dwimmmy results
    my @left  :=  left.eager;# XXX Should be .list.munch($max-elems) but that seems to be destructive
    my @right := right.eager;# same
    for ^$min-elems {
        @result[$_] := hyper(&operator, @left[$_], @right[$_], :$dwim-left, :$dwim-right);
    }

    # Check if 0 < $elems since if either side is empty and dwimmy (or both are empty),
    # and so @result should just remain empty.
    # If $elems < $max-elems, on the other hand, we still have more dwimmy results to generate
    if 0 < $left-elems < $max-elems {
        if $left-whatev {
            my $last-elem := @left[$left-elems - 1];
            for $left-elems..^$max-elems {
                @result[$_] := hyper(&operator, $last-elem, @right[$_], :$dwim-left, :$dwim-right);
            }
        } else {
            for $left-elems..^$max-elems {
                @result[$_] := hyper(&operator, @left[$_ % $left-elems], @right[$_], :$dwim-left, :$dwim-right);
            }
        }
    } elsif 0 < $right-elems < $max-elems {
        if $right-whatev {
            my $last-elem := @right[$right-elems - 1];
            for $right-elems..^$max-elems {
                @result[$_] := hyper(&operator, @left[$_], $last-elem, :$dwim-left, :$dwim-right);
            }
        } else {
            for $right-elems..^$max-elems {
                @result[$_] := hyper(&operator, @left[$_], @right[$_ % $right-elems], :$dwim-left, :$dwim-right);
            }
        }
    }

    # Coerce to the original type
    my $type = left.WHAT;
    nqp::iscont(left) ?? $type(@result.eager).item !! $type(@result.eager)
}

multi sub hyper(\op, \obj) {
    # fake it till we get a nodal trait
    my $nodal = True;

    $nodal ?? flatmap(op, obj) !! deepmap(op,obj);
}

proto sub deepmap(|) { * }

multi sub deepmap(\op, \obj) {
    my Mu $rpa := nqp::list();
    my Mu $items := nqp::p6listitems(obj.flat.eager);
    my Mu $o;
    # We process the elements in two passes, end to start, to
    # prevent users from relying on a sequential ordering of hyper.
    # Also, starting at the end pre-allocates $rpa for us.
    my int $i = nqp::elems($items) - 1;
    nqp::while(
        nqp::isge_i($i, 0),
        nqp::stmts(
            ($o := nqp::atpos($items, $i)),
            nqp::bindpos($rpa, $i,
                nqp::if(nqp::istype($o, Iterable),
                        $o.new(deepmap(op, $o)).item,
                        op.($o))),
            $i = nqp::sub_i($i, 2)
        )
    );
    $i = nqp::elems($items) - 2;
    nqp::while(
        nqp::isge_i($i, 0),
        nqp::stmts(
            ($o := nqp::atpos($items, $i)),
            nqp::bindpos($rpa, $i,
                nqp::if(nqp::istype($o, Iterable),
                        $o.new(deepmap(op, $o)).item,
                        op.($o))),
            $i = nqp::sub_i($i, 2)
        )
    );
    nqp::p6parcel($rpa, Nil);
}

multi sub deepmap(\op, Associative \h) {
    my @keys = h.keys;
    hash @keys Z deepmap(op, h{@keys})
}

proto sub flatmap(|) { * }
multi sub flatmap(\op, \obj) {
    my Mu $rpa := nqp::list();
    my Mu $items := nqp::p6listitems(obj.flat.eager);
    my Mu $o;
    # We process the elements in two passes, end to start, to
    # prevent users from relying on a sequential ordering of hyper.
    # Also, starting at the end pre-allocates $rpa for us.
    my int $i = nqp::elems($items) - 1;
    nqp::while(
        nqp::isge_i($i, 0),
        nqp::stmts(
            ($o := nqp::atpos($items, $i)),
            nqp::bindpos($rpa, $i,
                nqp::if(Mu,             # hack cuz I don't understand nqp
                        $o.new(flatmap(op, $o)).item,
                        op.($o))),
            $i = nqp::sub_i($i, 2)
        )
    );
    $i = nqp::elems($items) - 2;
    nqp::while(
        nqp::isge_i($i, 0),
        nqp::stmts(
            ($o := nqp::atpos($items, $i)),
            nqp::bindpos($rpa, $i,
                nqp::if(Mu,             # hack cuz I don't understand nqp
                        $o.new(flatmap(op, $o)).item,
                        op.($o))),
            $i = nqp::sub_i($i, 2)
        )
    );
    nqp::p6parcel($rpa, Nil);
}

multi sub flatmap(\op, Associative \h) {
    my @keys = h.keys;
    hash @keys Z flatmap(op, h{@keys})
}

proto sub duckmap(|) { * }
multi sub duckmap(\op, \obj) {
    flatmap(-> \arg { try { op.(arg) } // try { duckmap(op,arg) } }, obj);
}

multi sub duckmap(\op, Associative \h) {
    my @keys = h.keys;
    hash @keys Z duckmap(op, h{@keys})
}

multi sub hyper(&op, Associative:D \left, Associative:D \right, :$dwim-left, :$dwim-right) {
    my %keyset;
    if !$dwim-left {
        %keyset{$_} = 1 for left.keys;
    }
    else {
        %keyset{$_} = 1 if right.EXISTS-KEY($_) for left.keys;
    }
    if !$dwim-right {
        %keyset{$_} = 1 for right.keys;
    }
    my @keys := %keyset.keys;
    my $type = left.WHAT;
    my %result := $type(@keys Z hyper(&op, left{@keys}, right{@keys}, :$dwim-left, :$dwim-right));
    nqp::iscont(left) ?? $%result !! %result;
}

multi sub hyper(&op, Associative:D \left, \right, :$dwim-left, :$dwim-right) {
    my @keys = left.keys;
    my $type = left.WHAT;
    my %result := $type(@keys Z hyper(&op, left{@keys}, right, :$dwim-left, :$dwim-right));
    nqp::iscont(left) ?? $%result !! %result;
}

multi sub hyper(&op, \left, Associative:D \right, :$dwim-left, :$dwim-right) {
    my @keys = right.keys;
    my $type = right.WHAT;
    my %result := $type(@keys Z hyper(&op, left, right{@keys}, :$dwim-left, :$dwim-right));
    nqp::iscont(right) ?? $%result !! %result;
}

# vim: ft=perl6 expandtab sw=4
