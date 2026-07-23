#!/usr/bin/env bats

@test "health_check.sh exists" {
    [ -f health_check.sh ]
}

@test "health_check.sh is executable" {
    [ -x health_check.sh ]
}

@test "health_check.sh syntax" {
    run bash -n health_check.sh
    [ "$status" -eq 0 ]
}
