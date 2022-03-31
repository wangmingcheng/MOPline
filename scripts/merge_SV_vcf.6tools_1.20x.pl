#!/usr/bin/perl -w
use strict;
use File::Basename;
use FindBin qw($Bin);
use Getopt::Long;
use Pod::Usage;

my $sample_list = '';

my $read_length = 150;

$read_length = '';

my $non_human = 0;

my $ref_index = '';

my $merge_dir = 'Merge_6tools_1';

my $group = '';

my $help;

GetOptions(
    'sample|s=s' => \$sample_list,
    'dir|d=s' => \$merge_dir,
    'read_len|rl=i' => \$read_length,
    'nonhuman|nh=i' => \$non_human,
    'refi|r=s' => \$ref_index,
    'group|g=s' => \$group,
    'help' => \$help
) or pod2usage(-verbose => 0);
pod2usage(-verbose => 0) if $help;

=head1 SYNOPSIS

  merge_SV_vcf.6tools_1.20x.pl -s <sample-list-file or a sample name> -rl <read_length> (-nh 1 if sample is a non-human species)
  output vcf file name: ${sample_name}.Merge.ALL.vcf
  Tools used: MATCHCLIP, inGAP, CNVnator, Manta, Wham, MELT

  Options:
   --sample or -s <STR>         a list file of sample names or bam files containing sample names (or a sample name can be specified if a single sample is treated)
   --dir or -d <STR>            output directory name, which contains output vcf files [default: Merge_6tools_1]
   --group or -g <STR>          group ID to be added to output vcf file name, for distingwishing from other sample groups (output vcf file: ${groupID}.${sample_name}.Merge.ALL.vcf) [optional]
   --read_length or -rl <STR>   mean read length in bam files used for SV calling
   --non_human or -nh  <INT>    samples are non-human species (human: 0, non-human: 1) [default: 0]
   --refi or -r <STR>           reference fasta index (*.fai) file (only for non-human sample)
   --help or -h                 output help message
   
=cut

my $script_dir = $Bin;
$script_dir = "$ENV{MOPLINE_DIR}/scripts" if (exists $ENV{MOPLINE_DIR});

my $path = '';
my @ID_list;

my $work_dir = `pwd`;
chomp $work_dir;

my @tools = ('MATCHCLIP', 'inGAP', 'CNVnator', 'Manta', 'Wham', 'MELT');

my $genome_size = 1;

if ($non_human == 1){
    die ("ref fasta index file is not specified:\n") if ($ref_index eq '');
    my $size = 0;
    open (FILE, $ref_index) or die "$ref_index is not found: $!\n";
    while (my $line = <FILE>){
        chomp $line;
        my ($chr, $s1, $s2) = split (/\t/, $line);
        $size = $s1 + $s2;
    }
    close (FILE);
    $genome_size = int ($size / 3100000000 * 100 + 0.5) / 100;
}

if (-s $sample_list){
    open (FILE, $sample_list) or die "$sample_list is not found: $!\n";
    while (my $line = <FILE>){
        chomp $line;
        next if ($line =~ /^$|^#/);
        my @line = split (/\t/, $line);
        my $bam = basename ($line[0]);
        if ($bam =~ /^([^\.]+).*\.bam$/){
            my $ID = $1;
            push @ID_list, $ID;
        }
        else{
            push @ID_list, $line[0];
        }
    }
    close (FILE);
}
else{
    push @ID_list, $sample_list;
}

foreach my $ID (@ID_list){
    print STDERR "\n## ID: $ID ##\n";
    system ("mkdir $ID/$merge_dir") if (!-d "$ID/$merge_dir");
    system ("rm -f $ID/$merge_dir/*.vcf");

    my $ins_tools = 'inGAP Manta Wham MELT';
        
    system ("$script_dir/merge_SV_calls_multi_tools.pl -st INS -rl $read_length -s $ID -d $ID -t $ins_tools -nh $non_human > $ID/$merge_dir/Merge.INS.4tools.simple.vcf");
    
    my $inGAP_ins_mr1 = 10;
    my $inGAP_ins_mr2 = 18;
    my $inGAP_del_mr1 = 12;
    
    my $inGAP_vcf = "$ID/inGAP/inGAP.$ID.vcf";
    
    my $ins_num = `grep 'SVTYPE=INS' $inGAP_vcf | wc -l`;
    chomp $ins_num;
    
    if ($non_human == 0){
        if ($ins_num > 3200){
            my $mread_set = `$script_dir/stat_inGAP_INS.pl $inGAP_vcf 3200 2700`;
            chomp $mread_set;
            if ($mread_set =~ /(\d+),(\d+)/){
                $inGAP_ins_mr1 = $1 if ($1 > 0);
                $inGAP_ins_mr2 = $2 if ($2 > 0);
            }
        }
    }
    else{
        if ($ins_num > 3200 * $genome_size){
            my $max_num1 = int ($ins_num * 3200 / 5000 + 0.5);
            my $max_num2 = int (3000 * $genome_size + 0.5);
            my $mread_set = `$script_dir/stat_inGAP_INS.pl $inGAP_vcf $max_num1 $max_num2`;
            chomp $mread_set;
            if ($mread_set =~ /(\d+),(\d+)/){
                $inGAP_ins_mr1 = $1 if ($1 > 0);
                $inGAP_ins_mr2 = $2 if ($2 > 0);
                $inGAP_ins_mr1 = 50 if ($1 == 0);
                $inGAP_ins_mr2 = 100 if ($1 == 0);
            }
        }
    }
    
    my $del_num = `grep 'SVTYPE=DEL' $inGAP_vcf | wc -l`;
    chomp $del_num;
    
    if ($del_num > 60000 * $genome_size){
        $inGAP_del_mr1 = 18;
    }
    elsif ($del_num > 40000 * $genome_size){
        $inGAP_del_mr1 = 16;
    }
    elsif ($del_num > 20000 * $genome_size){
        $inGAP_del_mr1 = 14;
    }
    
    print STDERR "inGAP mr1: $inGAP_ins_mr1 inGAP mr2: $inGAP_ins_mr2\n";
    
    my $ins_set = "Manta:3=inGAP:$inGAP_ins_mr1 Wham:3=inGAP:$inGAP_ins_mr1 Manta:3=Wham:3 inGAP:$inGAP_ins_mr2 Manta:18 MELT:3";
   
    system ("$script_dir/merge_SV_calls_multi_tools_filter.pl -t INS -ins $ins_set -v $ID/$merge_dir/Merge.INS.4tools.simple.vcf > $ID/$merge_dir/MOP.Merge.INS.4tools.vcf");
    
    my $del_tools = 'CNVnator inGAP Manta MATCHCLIP Wham';
        
    system ("$script_dir/merge_SV_calls_multi_tools_eachSize.pl -st DEL -rl $read_length -s $ID -d $ID -t $del_tools -nh $non_human > $ID/$merge_dir/Merge.DEL.5tools.simple.vcf");
    
    my $del_set_S = 'Manta:3=inGAP:6 Wham:4=Manta:3 Wham:4=inGAP:6 MATCHCLIP:4=inGAP:6 MATCHCLIP:4=Manta:3 MATCHCLIP:4=Wham:4';
    my $del_set_M = 'CNVnator:3=# MATCHCLIP:3=Wham:3 MATCHCLIP:3=inGAP:4 Manta:3=Wham:3 Manta:3=inGAP:4 Manta:3=MATCHCLIP:3 Wham:3=inGAP:4 CNVnator:7';
    my $del_set_L = "CNVnator:3=# Manta:3=Wham:3 MATCHCLIP:3=Wham:3 MATCHCLIP:3=Manta:3 MATCHCLIP:3=inGAP:5 Manta:3=inGAP:5 Wham:3=inGAP:5 CNVnator:8 inGAP:$inGAP_del_mr1 Wham:6 MATCHCLIP:4";
    
    system ("$script_dir/merge_SV_calls_multi_tools_eachSize.pl -st DEL -rl $read_length -s $ID -d $ID -t $del_tools -nh $non_human > $ID/$merge_dir/Merge.DEL.5tools.simple.vcf");
    
    my $dup_tools = 'CNVnator inGAP Manta MATCHCLIP Wham';
        
    system ("$script_dir/merge_SV_calls_multi_tools_eachSize.pl -st DUP -rl $read_length -s $ID -d $ID -t $dup_tools -nh $non_human > $ID/$merge_dir/Merge.DUP.5tools.simple.vcf");
    
    my $dup_set_S = 'MATCHCLIP:3=Manta:3 MATCHCLIP:3=Wham:3 Wham:3=Manta:3 MATCHCLIP:7';
    my $dup_set_M = 'CNVnator:3=# inGAP:5=Manta:3 CNVnator:6';
    my $dup_set_L = 'CNVnator:2=Manta:3 Manta:3=Wham:3 CNVnator:2=inGAP:3 CNVnator:8 inGAP:4';
    
    system ("$script_dir/merge_SV_calls_multi_tools_filter.pl -t DUP -dup_s $dup_set_S -dup_m $dup_set_M -dup_l $dup_set_L -v $ID/$merge_dir/Merge.DUP.5tools.simple.vcf > $ID/$merge_dir/MOP.Merge.DUP.5tools.vcf");
        
    my $inv_tools = 'inGAP Manta Wham';
        
    system ("$script_dir/merge_SV_calls_multi_tools_eachSize.pl -st INV -rl $read_length -s $ID -d $ID -t $inv_tools -nh $non_human > $ID/$merge_dir/Merge.INV.3tools.simple.vcf");
    
    my $inv_set_S = 'inGAP:8=Manta:14 Wham:12=inGAP:8 Manta:14=Wham:12';
    my $inv_set_M = 'inGAP:3=Manta:3 Wham:5=inGAP:3 Manta:3=Wham:5';
    my $inv_set_L = 'inGAP:4=Manta:3 Wham:5=inGAP:4 Manta:3=Wham:5';
    
    system ("$script_dir/merge_SV_calls_multi_tools_filter.pl -t INV -inv_s $inv_set_S -inv_m $inv_set_M -inv_l $inv_set_L -v $ID/$merge_dir/Merge.INV.3tools.simple.vcf > $ID/$merge_dir/MOP.Merge.INV.3tools.vcf");
    
    my $out_vcf = "$ID/$merge_dir/$ID.Merge.ALL.vcf";
    $out_vcf = "$ID/$merge_dir/$group.$ID.Merge.ALL.vcf" if ($group ne '');
    
    system ("$script_dir/merge_SV_calls_ALLtype.pl -rl $read_length -v $ID/$merge_dir/MOP.Merge.DEL.5tools.vcf $ID/$merge_dir/MOP.Merge.INS.4tools.vcf $ID/$merge_dir/MOP.Merge.DUP.5tools.vcf $ID/$merge_dir/MOP.Merge.INV.3tools.vcf > $out_vcf");
    
    system ("rm $ID/$merge_dir/$group.$ID.Merge.ALL.noGT.vcf") if (-f "$ID/$merge_dir/$group.$ID.Merge.ALL.noGT.vcf");
}

 