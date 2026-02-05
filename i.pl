#!/usr/bin/perl
use strict; use warnings;

sub set_attr { my($tag,$attr,$val)=@_; $tag =~ s/(\b\Q$attr\E\s*=\s*")([^"]*)(")/$1$val$3/ or $tag =~ s/>/ $attr="$val">/; $tag }

my ($in,$out)=@ARGV; die "Usage: $0 input.xml [output.xml]\n" unless $in;
open(my $fh,'<',$in) or die "Cannot open '$in': $!\n"; local $/; my $xml=<$fh>; close $fh;

# ---- applicationGroup: replace ODAPPLID + keep indentation of </applicationGroup> ----
$xml =~ s{(^([ \t]*)<applicationGroup\b[^>]*>)(.*?)(</applicationGroup>)}{
    my($group_open,$group_indent,$group_body,$group_close)=($1,$2,$3,$4);
    my($field_indent)= $group_body =~ /(?:^|\n)([ \t]*)<field\b/i; $field_indent ||= $group_indent."        ";

    $group_body =~ s{^[ \t]*<field\b[^>]*\bname\s*=\s*(['"])ODAPPLID\1[^>]*(?:[ \t]*/>[ \t]*\r?\n?|[ \t]*>.*?</field>[ \t]*\r?\n?)}{}gmsi;

    my $mapping_indent=$field_indent.'        ';
    my $odapplid_block=$field_indent.'<field name="ODAPPLID" type="Filter" dataType="string" uniqueID="false" >'."\n".
                       $mapping_indent.'<mapping dbValue="A " displayedValue="FORMAT1" />'."\n".
                       $mapping_indent.'<mapping dbValue="B " displayedValue="FORMAT2" />'."\n".
                       $field_indent.'</field>'."\n";

    $group_body =~ s{^([ \t]*<permission\b)}{$odapplid_block$1}m or $group_body =~ s/(\n[ \t]*)\z/$odapplid_block$1/s or ($group_body.="\n$odapplid_block");
    $group_body =~ s/\n\z/\n$group_indent/; $group_body.="\n$group_indent" unless $group_body =~ /\n\Q$group_indent\E\z/s;

    $group_open.$group_body.$group_close
}egmsx;

# ---- application: force identifier="A ", duplicate as B, PARTNO defaultValue in B only ----
$xml =~ s{(^([ \t]*)<application\b([^>]*)>)(.*?)(</application>)}{
    my($app_indent,$app_attrs,$app_body,$app_close)=($2,$3,$4,$5);
    my $app_open=$app_indent."<application$app_attrs>";
    my($app_name)=$app_open =~ /\bname\s*=\s*"([^"]+)"/i;

    my $appA_open=set_attr($app_open,'identifier','A ');
    my $appA_block=$appA_open.$app_body.$app_close;

    my $appB_name=$app_name; $appB_name =~ s/^./B/;
    my $appB_open=set_attr(set_attr($appA_open,'name',$appB_name),'identifier','B ');

    my $appB_body=$app_body;
    $appB_body =~ s{(<preprocessParm\b[^>]*\bdbName\s*=\s*(['"])PARTNO\2[^>]*)(\s*/?>)}{
        my($parm_start,$parm_end)=($1,$3);
        $parm_start =~ s/\bdefaultValue\s*=\s*"[^"]*"/defaultValue="000001"/ or $parm_start.=' defaultValue="000001"';
        $parm_start.$parm_end
    }egmsi;

    $appA_block."\n".$appB_open.$appB_body.$app_close
}egmsx;

if ($out) { open(my $oh,'>',$out) or die "Cannot write '$out': $!\n"; print {$oh} $xml; close $oh or die "Write error '$out': $!\n"; }
else { print $xml; }
