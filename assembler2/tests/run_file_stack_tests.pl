#!/usr/bin/env perl
#
# Test runner for file stack component
# Usage: ./run_file_stack_tests.pl [test_file] [test_name_filter]

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Basename;
use Cwd qw(abs_path);

my $SCRIPT_DIR = dirname(abs_path(__FILE__));
my $BASE_DIR = dirname($SCRIPT_DIR);
my $TEST_PROG = "$BASE_DIR/out/file_stack_test.out";
my $EMULATOR = "$BASE_DIR/emulator.out";
my $TEST_FILE = $ARGV[0] // "$SCRIPT_DIR/file_stack_tests.txt";
my $FILTER = $ARGV[1] // '';

my ($passed, $failed, $skipped) = (0, 0, 0);

# ANSI colors
my $RED = "\033[0;31m";
my $GREEN = "\033[0;32m";
my $YELLOW = "\033[0;33m";
my $NC = "\033[0m";

# Parse test file into array of test hashes
sub parse_tests {
    my ($file) = @_;
    my @tests;
    my $current;
    my $section = '';      # Current section: '', 'file', 'stdout', 'stderr'
    my $section_name = ''; # For FILE sections, the filename

    open my $fh, '<', $file or die "Cannot open $file: $!";
    while (<$fh>) {
        chomp;

        # Skip comments and blank lines outside sections
        if ($section eq '') {
            next if /^\s*#/;
            next if /^\s*$/;
        }

        # Test separator
        if (/^---$/) {
            push @tests, $current if $current && $current->{name};
            $current = { files => {} };
            $section = '';
            next;
        }

        # Field parsers
        if (/^NAME:\s*(.*)/) {
            $current->{name} = $1;
            $section = '';
        }
        elsif (/^MODE:\s*(.*)/) {
            $current->{mode} = $1;
            $section = '';
        }
        elsif (/^FILE\s+(\S+):/) {
            $section = 'file';
            $section_name = $1;
            $current->{files}{$section_name} = '';
            $current->{main_file} //= $section_name;  # First file is main
        }
        elsif (/^EXPECT_STDOUT:/) {
            $section = 'stdout';
            $current->{expect_stdout} = '';
        }
        elsif (/^EXPECT_STDERR:/) {
            $section = 'stderr';
            $current->{expect_stderr} = '';
        }
        elsif ($section eq 'file') {
            # Strip "N: " prefix (with optional space after colon)
            s/^\d+:\s?//;
            $current->{files}{$section_name} .= "$_\n";
        }
        elsif ($section eq 'stdout') {
            # Skip comment and blank lines in expected output sections
            next if /^\s*#/;
            next if /^\s*$/;
            $current->{expect_stdout} .= "$_\n";
        }
        elsif ($section eq 'stderr') {
            # Skip comment and blank lines in expected output sections
            next if /^\s*#/;
            next if /^\s*$/;
            $current->{expect_stderr} .= "$_\n";
        }
    }
    push @tests, $current if $current && $current->{name};
    close $fh;

    return @tests;
}

# Run a single test
sub run_test {
    my ($test) = @_;
    my $name = $test->{name};

    # Apply filter
    if ($FILTER && $name !~ /\Q$FILTER\E/) {
        return;
    }

    printf "  %-40s ", $name;

    # Check for required fields
    if (!$test->{mode} || !$test->{main_file}) {
        print "${YELLOW}SKIP${NC} (missing mode or file)\n";
        $skipped++;
        return;
    }

    # Create temp directory for test files
    my $tmpdir = tempdir(CLEANUP => 1);

    # Write input files
    for my $filename (keys %{$test->{files}}) {
        my $content = $test->{files}{$filename};
        # Don't strip trailing newline - files naturally end with newlines
        # Transform @include directives to use absolute paths (for nested and memory modes)
        if ($test->{mode} eq 'nested' || $test->{mode} eq 'memory') {
            $content =~ s/\@include\s+(\S+)/\@include $tmpdir\/$1/g;
        }

        # Handle subdirectories in filename
        my $filepath = "$tmpdir/$filename";
        my $filedir = dirname($filepath);
        if ($filedir ne $tmpdir) {
            system("mkdir", "-p", $filedir);
        }

        open my $fh, '>', $filepath or die "Cannot write $filepath: $!";
        print $fh $content;
        close $fh;
    }

    # Run the test program
    my $main_file = "$tmpdir/" . $test->{main_file};
    my $mode = $test->{mode};

    my $stdout_file = "$tmpdir/stdout";
    my $stderr_file = "$tmpdir/stderr";

    # Run emulator with test program
    # Note: emulator writes to 4th arg (output file), not stdout
    # Start address 200 = $0200 where test program is loaded
    my $cmd = "$EMULATOR $TEST_PROG 200 /dev/null $stdout_file $mode $main_file 2>$stderr_file";
    system($cmd);
    my $exit_code = $? >> 8;

    # Read actual output
    my $actual_stdout = read_file($stdout_file);
    my $actual_stderr = read_file($stderr_file);

    # Filter emulator noise from stderr
    $actual_stderr =~ s/^.*executed \d+ cycles\n//mg;
    $actual_stderr =~ s/^File \d+ was not closed\n//mg;
    $actual_stderr =~ s/^out\/.*\n//mg;
    $actual_stderr =~ s/^.*\.out \d+ \/dev\/null.*\n//mg;

    # Normalize (strip trailing whitespace from each line and end)
    $actual_stdout = normalize($actual_stdout);
    $actual_stderr = normalize($actual_stderr);

    my $expect_stdout = normalize($test->{expect_stdout} // '');
    my $expect_stderr = normalize($test->{expect_stderr} // '');

    # Compare
    my $ok = 1;
    my @details;

    if ($expect_stdout ne '' || $actual_stdout ne '') {
        if ($actual_stdout ne $expect_stdout) {
            $ok = 0;
            push @details, "  Expected stdout:";
            push @details, indent($expect_stdout);
            push @details, "  Actual stdout:";
            push @details, indent($actual_stdout);
        }
    }

    if ($expect_stderr ne '' || $actual_stderr ne '') {
        if ($actual_stderr ne $expect_stderr) {
            $ok = 0;
            push @details, "  Expected stderr:";
            push @details, indent($expect_stderr);
            push @details, "  Actual stderr:";
            push @details, indent($actual_stderr);
        }
    }

    if ($ok) {
        print "${GREEN}PASS${NC}\n";
        $passed++;
    } else {
        print "${RED}FAIL${NC}\n";
        print "$_\n" for @details;
        $failed++;
    }
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or return '';
    local $/;
    my $content = <$fh> // '';
    close $fh;
    return $content;
}

sub normalize {
    my ($text) = @_;
    return '' if !defined $text;
    # Strip trailing whitespace from each line
    $text =~ s/[ \t]+$//mg;
    # Strip trailing newlines
    $text =~ s/\n+$//;
    return $text;
}

sub indent {
    my ($text) = @_;
    return '    (empty)' if !defined $text || $text eq '';
    $text =~ s/^/    /mg;
    return $text;
}

# Check prerequisites
sub check_prereqs {
    unless (-x $EMULATOR) {
        die "Error: Emulator not found at $EMULATOR\nRun the build first.\n";
    }
    unless (-f $TEST_PROG) {
        die "Error: Test program not found at $TEST_PROG\nRun: ./emulator.out out/asm22_debug.out 2000 /dev/null /dev/null tests/file_stack_test.asm out/file_stack_test.out\n";
    }
    unless (-f $TEST_FILE) {
        die "Error: Test file not found at $TEST_FILE\n";
    }
}

# Main
check_prereqs();

print "=" x 40 . "\n";
print "File Stack Tests\n";
print "=" x 40 . "\n\n";

print "Running tests from " . basename($TEST_FILE) . "\n\n";

my @tests = parse_tests($TEST_FILE);
run_test($_) for @tests;

print "\n" . "=" x 40 . "\n";
print "Results: ${GREEN}$passed passed${NC}";
print ", ${RED}$failed failed${NC}" if $failed;
print ", ${YELLOW}$skipped skipped${NC}" if $skipped;
print "\n" . "=" x 40 . "\n";

exit($failed > 0 ? 1 : 0);
