#!/bin/env perl

use Test::More;
use Test::UseAllModules;

BEGIN {
    plan tests => Test::UseAllModules::_get_module_list() + 0;
    all_uses_ok();
}
