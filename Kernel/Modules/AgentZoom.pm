# --
# Kernel/Modules/AgentZoom.pm - to get a closer view
# Copyright (C) 2001-2004 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: AgentZoom.pm,v 1.54 2004-04-06 09:05:54 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::Modules::AgentZoom;

use strict;
use Kernel::System::CustomerUser;

use vars qw($VERSION);
$VERSION = '$Revision: 1.54 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;
   
    # allocate new hash for object 
    my $Self = {}; 
    bless ($Self, $Type);
    
    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }
    # check needed Opjects
    foreach (qw(ParamObject DBObject TicketObject LayoutObject LogObject
      QueueObject ConfigObject UserObject SessionObject)) {
        die "Got no $_!" if (!$Self->{$_});
    }
    # get params 
    $Self->{ArticleID} = $Self->{ParamObject}->GetParam(Param => 'ArticleID');
    $Self->{ZoomExpand} = $Self->{ParamObject}->GetParam(Param => 'ZoomExpand');
    $Self->{ZoomExpandSort} = $Self->{ParamObject}->GetParam(Param => 'ZoomExpandSort');
    if (!defined($Self->{ZoomExpand})) {
        $Self->{ZoomExpand} = $Self->{ConfigObject}->Get('TicketZoomExpand');
    }
    if (!defined($Self->{ZoomExpandSort})) {
        $Self->{ZoomExpandSort} = $Self->{ConfigObject}->Get('TicketZoomExpandSort');
    }
    $Self->{HighlightColor1} = $Self->{ConfigObject}->Get('HighlightColor1');
    $Self->{HighlightColor2} = $Self->{ConfigObject}->Get('HighlightColor2');
    # customer user object
    $Self->{CustomerUserObject} = Kernel::System::CustomerUser->new(%Param);
    return $Self;
}
# --
sub Run {
    my $Self = shift;
    my %Param = @_;
    my $Output;
    # --
    # check needed stuff
    # --
    if (!$Self->{TicketID}) {
        $Output = $Self->{LayoutObject}->Header(Title => 'Error');
        $Output .= $Self->{LayoutObject}->Error(
            Message => "No TicketID is given!",
            Comment => 'Please contact the admin.',
        );
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
    }
    # --
    # check permissions
    # --
    if (!$Self->{TicketObject}->Permission(
        Type => 'ro',
        TicketID => $Self->{TicketID},
        UserID => $Self->{UserID})) {
        # --
        # error screen, don't show ticket
        # --
        return $Self->{LayoutObject}->NoPermission(WithHeader => 'yes');
    }  
    # --
    # store last screen
    # --
    if ($Self->{Subaction} ne 'ShowHTMLeMail') {
      if (!$Self->{SessionObject}->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key => 'LastScreen',
        Value => $Self->{RequestedURL},
      )) {
        $Output = $Self->{LayoutObject}->Header(Title => 'Error');
        $Output .= $Self->{LayoutObject}->Error();
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
      }  
    }
    # get content
    my %Ticket = $Self->{TicketObject}->TicketGet(TicketID => $Self->{TicketID});
    my %TicketLink = $Self->{TicketObject}->TicketLinkGet(
        TicketID => $Self->{TicketID},
        UserID => $Self->{UserID},
    );
    my @ArticleBox = $Self->{TicketObject}->GetArticleContentIndex(TicketID => $Self->{TicketID});
    # --
    # return if HTML email
    # --
    if ($Self->{Subaction} eq 'ShowHTMLeMail') {
        # check needed ArticleID
        if (!$Self->{ArticleID}) {
            $Output = $Self->{LayoutObject}->Header(Title => 'Error');
            $Output .= $Self->{LayoutObject}->Error(Message => 'Need ArticleID!');
            $Output .= $Self->{LayoutObject}->Footer();
            return $Output;
        }
        # get article data
        my %Article = ();
        foreach my $ArticleTmp (@ArticleBox) {
            if ($ArticleTmp->{ArticleID} eq $Self->{ArticleID}) {
                %Article = %{$ArticleTmp};
            }
        }
        # check if article data exists
        if (!%Article) {
            $Output = $Self->{LayoutObject}->Header(Title => 'Error');
            $Output .= $Self->{LayoutObject}->Error(Message => 'Invalid ArticleID!');
            $Output .= $Self->{LayoutObject}->Footer();
            return $Output;
        }
        # if it is a html email, return here
        return $Self->MaskAgentZoomHTML(%Ticket, %Article);
    }
    # --
    # else show normal ticket zoom view
    # --
    # fetch all move queues
    my %MoveQueues = $Self->{TicketObject}->MoveList(
        TicketID => $Self->{TicketID},
        UserID => $Self->{UserID},
        Type => 'move_into',
    );
    # fetch all std. responses
    my %StdResponses = $Self->{QueueObject}->GetStdResponses(QueueID => $Ticket{QueueID});
    # user info
    my %UserInfo = $Self->{UserObject}->GetUserData(
        User => $Ticket{Owner},
        Cached => 1
    );
    # customer info
    my %CustomerData = ();
    if ($Self->{ConfigObject}->Get('ShowCustomerInfoZoom')) {
        if ($Ticket{CustomerUserID}) {
            %CustomerData = $Self->{CustomerUserObject}->CustomerUserDataGet(
                User => $Ticket{CustomerUserID},
            );
        }
        elsif ($Ticket{CustomerID}) {
            %CustomerData = $Self->{CustomerUserObject}->CustomerUserDataGet(
                CustomerID => $Ticket{CustomerID},
            );
        }
    }
    # --
    # genterate output
    # --
    $Output .= $Self->{LayoutObject}->Header(Area => 'Agent', Title => "Zoom Ticket");
    my %LockedData = $Self->{TicketObject}->GetLockedCount(UserID => $Self->{UserID});
    $Output .= $Self->{LayoutObject}->NavigationBar(LockData => \%LockedData);
    # --
    # show ticket
    # --
    $Output .= $Self->MaskAgentZoom(
        MoveQueues => \%MoveQueues,
        StdResponses => \%StdResponses,
        ArticleBox => \@ArticleBox,
        CustomerData => \%CustomerData,
        TicketTimeUnits => $Self->{TicketObject}->GetAccountedTime(%Ticket),
        %UserInfo,
        %Ticket,
        %TicketLink,
    );
    # add footer 
    $Output .= $Self->{LayoutObject}->Footer();
    # return output
    return $Output;
}
# --
sub MaskAgentZoom {
    my $Self = shift;
    my %Param = @_;
    $Param{Age} = $Self->{LayoutObject}->CustomerAge(Age => $Param{Age}, Space => ' ');
    if ($Param{UntilTime}) {
        if ($Param{UntilTime} < -1) {
            $Param{PendingUntil} = "<font color='$Self->{HighlightColor2}'>";
        }
        $Param{PendingUntil} .= $Self->{LayoutObject}->CustomerAge(Age => $Param{UntilTime}, Space => '<br>');
        if ($Param{UntilTime} < -1) {
            $Param{PendingUntil} .= "</font>";
        }
    }
    # --
    # get MoveQueuesStrg
    # --
    if ($Self->{ConfigObject}->Get('MoveType') =~ /^form$/i) {
        $Param{MoveQueuesStrg} = $Self->{LayoutObject}->AgentQueueListOption(
            Name => 'DestQueueID',
            Data => $Param{MoveQueues},
            SelectedID => $Param{QueueID},
        );
    }
    # --
    # customer info string 
    # --
    $Param{CustomerTable} = $Self->{LayoutObject}->AgentCustomerViewTable(
        Data => $Param{CustomerData},
        Max => $Self->{ConfigObject}->Get('ShowCustomerInfoZoomMaxSize'),
    );
    # --
    # build article stuff
    # --
    my $BaseLink = $Self->{LayoutObject}->{Baselink}."TicketID=$Self->{TicketID}&QueueID=$Self->{QueueID}&";
    my @ArticleBox = @{$Param{ArticleBox}};
    # get selected or last customer article
    my $CounterArray = 0;
    my $ArticleID;
    if ($Self->{ArticleID}) {
        $ArticleID = $Self->{ArticleID};
    }
    else {
        # set first article
        if (@ArticleBox) {
            $ArticleID = $ArticleBox[0]->{ArticleID};
        }
        # get last customer article
        foreach my $ArticleTmp (@ArticleBox) {
            if ($ArticleTmp->{SenderType} eq 'customer') {
                $ArticleID = $ArticleTmp->{ArticleID};
            }
        }
    }
    # --
    # build thread string
    # --
    my $ThreadStrg = '';
    my $Counter = '';
    my $Space = '';
    my $LastSenderType = '';
    my $TicketOverTime = 0;
    $Param{ArticleStrg} = '<table border="0" width="100%" cellspacing="0" cellpadding="0">';
    foreach my $ArticleTmp (@ArticleBox) {
      my %Article = %$ArticleTmp;
      $TicketOverTime = $Article{TicketOverTime}; 
      if ($Article{ArticleType} !~ /^email-notification/i) { 
        my $TmpSubject = $Article{Subject};
        my $TicketHook = $Self->{ConfigObject}->Get('TicketHook') || '';
        $TmpSubject =~ s/^..: //;
        $TmpSubject =~ s/\[$TicketHook: $Article{TicketNumber}\] //g;
        $ThreadStrg .= '<tr class="'.$Article{SenderType}.'-'.$Article{ArticleType}.'"><td class="small">';
        $ThreadStrg .= '<div title="'.$Self->{LayoutObject}->Ascii2Html(Text => $TmpSubject, Max => 200).' - $TimeLong{"'.$Article{Created}.'"}">';
        if ($LastSenderType ne $Article{SenderType}) {
            $Counter .= "&nbsp;&nbsp;";
            $Space = "$Counter |--&gt;";
        }
        $LastSenderType = $Article{SenderType};
        $ThreadStrg .= "$Space";
        # --
        # if this is the shown article -=> add <b>
        # --
        if ($ArticleID eq $Article{ArticleID}) {
            $ThreadStrg .= '&gt;&gt;<i><b><u>';
        }
        # --
        # the full part thread string
        # --
        $ThreadStrg .= "<a href=\"$BaseLink"."Action=AgentZoom&ArticleID=$Article{ArticleID}#$Article{ArticleID}\"" .
           'onmouseover="window.status=\''."\$Text{\"$Article{SenderType}\"} (".
           "\$Text{\"$Article{ArticleType}\"})".'\'; return true;" onmouseout="window.status=\'\';">'.
           "\$Text{\"$Article{SenderType}\"} (\$Text{\"$Article{ArticleType}\"})</a> ";
        if ($Article{ArticleType} =~ /^email/) {
            $ThreadStrg .= " (<a href=\"$BaseLink"."Action=AgentPlain&ArticleID=$Article{ArticleID}\"".
             'onmouseover="window.status=\'$Text{"plain"}'.
             '\'; return true;" onmouseout="window.status=\'\';">$Text{"plain"}</a>)';
        }
        $ThreadStrg .= '&nbsp;-&nbsp;'.$Self->{LayoutObject}->Ascii2Html(Text => $TmpSubject, Max => 20).'&nbsp;-&nbsp;$TimeLong{"'.$Article{Created}.'"}';
        # --
        # if this is the shown article -=> add </b>
        # --
        if ($ArticleID eq $Article{ArticleID}) { 
            $ThreadStrg .= '</u></b></i>';
        }
        $ThreadStrg .= '</div></td></tr>';
      }
    }
    $ThreadStrg .= '</table>';
    $Param{ArticleStrg} .= $ThreadStrg;
    # --
    # prepare escalation time (if needed)
    # --
    if ($Param{Answered}) {
        $Param{TicketOverTime} = '$Text{"none - answered"}';
    }
    elsif ($TicketOverTime) {
      # colloring  
      if ($TicketOverTime <= -60*20) {
          $Param{TicketOverTimeFont} = "<font color='$Self->{HighlightColor2}'>";
          $Param{TicketOverTimeFontEnd} = '</font>';
      }
      elsif ($TicketOverTime <= -60*40) {
          $Param{TicketOverTimeFont} = "<font color='$Self->{HighlightColor1}'>";
          $Param{TicketOverTimeFontEnd} = '</font>';
      }

      $Param{TicketOverTime} = $Self->{LayoutObject}->CustomerAge(
          Age => $TicketOverTime,
          Space => '<br>',
      );
      if ($Param{TicketOverTimeFont} && $Param{TicketOverTimeFontEnd}) {
        $Param{TicketOverTime} = $Param{TicketOverTimeFont}.
            $Param{TicketOverTime}.$Param{TicketOverTimeFontEnd};
      }
    }
    else {
        $Param{TicketOverTime} = '-';
    }
    # --
    # get shown article(s)
    # --
    my @NewArticleBox = ();
    if (!$Self->{ZoomExpand}) {
        foreach my $ArticleTmp (@ArticleBox) {
            if ($ArticleID eq $ArticleTmp->{ArticleID}) {
                push(@NewArticleBox, $ArticleTmp);
            }
        }
    }
    else {
        # resort article order
        if ($Self->{ZoomExpandSort} eq 'reverse') {
            @ArticleBox = reverse(@ArticleBox);
        }
      # show no email-notification* article
      foreach my $ArticleTmp (@ArticleBox) {
          my %Article = %$ArticleTmp;
          if ($Article{ArticleType} !~ /^email-notification/i) {
              push (@NewArticleBox, $ArticleTmp);
          }
      }
    }
    # --
    # build shown article(s)
    # --
    $Param{TicketStatus} .= $Self->{LayoutObject}->Output(
        TemplateFile => 'AgentZoomStatus',
        Data => {%Param},
    );
    my $BodyOutput = '';
    foreach my $ArticleTmp (@NewArticleBox) {
        my %Article = %$ArticleTmp;
        # delete ArticleStrg and TicketStatus if it's not the first shown article
        if ($BodyOutput) {
            $Param{ArticleStrg} = '';
            $Param{TicketStatus} = '';
        }
        # get StdResponsesStrg
        $Param{StdResponsesStrg} = $Self->{LayoutObject}->TicketStdResponseString(
            StdResponsesRef => $Param{StdResponses},
            TicketID => $Param{TicketID},
            ArticleID => $Article{ArticleID},
        );
        # get attacment string
        my %AtmIndex = ();
        if ($Article{Atms}) {
            %AtmIndex = %{$Article{Atms}};
        }
        $Article{"ATM"} = '';
        foreach (keys %AtmIndex) {
            $AtmIndex{$_} = $Self->{LayoutObject}->Ascii2Html(Text => $AtmIndex{$_});
            $Article{"ATM"} .= '<a href="$Env{"Baselink"}Action=AgentAttachment&'.
              "ArticleID=$Article{ArticleID}&FileID=$_\" target=\"attachment\" ".
              "onmouseover=\"window.status='\$Text{\"Download\"}: $AtmIndex{$_}';".
              ' return true;" onmouseout="window.status=\'\';">'.
              $AtmIndex{$_}.'</a><br> ';
        }
        # do some strips && quoting
        foreach (qw(From To Cc Subject Body)) {
            $Article{$_} = $Self->{LayoutObject}->{LanguageObject}->CharsetConvert(
                Text => $Article{$_},
                From => $Article{ContentCharset},
            );
        }
        # check if just a only html email
        if (my $MimeTypeText = $Self->{LayoutObject}->CheckMimeType(%Param, %Article)) {
            $Article{"BodyNote"} = $MimeTypeText;
            $Article{"Body"} = '';
        }
        else {
            # html quoting
            $Article{"Body"} = $Self->{LayoutObject}->Ascii2Html(
                NewLine => $Self->{ConfigObject}->Get('ViewableTicketNewLine') || 85,
                Text => $Article{Body},
                VMax => $Self->{ConfigObject}->Get('ViewableTicketLinesZoom') || 5000,
                HTMLResultMode => 1,
            );
            # link quoting
            $Article{"Body"} = $Self->{LayoutObject}->LinkQuote(
                Text => $Article{"Body"},
            );
            # do charset check
            if (my $CharsetText = $Self->{LayoutObject}->CheckCharset(
                ContentCharset => $Article{ContentCharset},
                TicketID => $Param{TicketID},
                ArticleID => $Article{ArticleID} )) {
                $Article{"TextNote"} = $CharsetText;
            }
        }
        # select the output template
        if ($Article{ArticleType} =~ /^note/i) {
            # without compose links!
            if ($Self->{ConfigObject}->Get('AgentCanBeCustomer') && $Param{CustomerUserID} =~ /^$Self->{UserLogin}$/i) {
              $Article{TicketAnswer} = $Self->{LayoutObject}->Output(
                TemplateFile => 'AgentZoomAgentIsCustomer',
                Data => {%Param, %Article},
              );
            }
            $Article{TicketArticle} = $Self->{LayoutObject}->Output(
                TemplateFile => 'AgentZoomArticle',
                Data => {%Param, %Article},
            );
            $BodyOutput .= $Self->{LayoutObject}->Output(
                TemplateFile => 'AgentZoomBody', 
                Data => {%Param, %Article},
            );
        }
        else {
            # without all!
            if ($Self->{ConfigObject}->Get('AgentCanBeCustomer') && $Param{CustomerUserID} =~ /^$Self->{UserLogin}$/i) {
              $Article{TicketAnswer} = $Self->{LayoutObject}->Output(
                TemplateFile => 'AgentZoomAgentIsCustomer',
                Data => {%Param, %Article},
              );
            }
            else {
              $Article{TicketAnswer} = $Self->{LayoutObject}->Output(
                  TemplateFile => 'AgentZoomAnswer',
                  Data => {%Param, %Article},
              );
              $Article{TicketArticle} = $Self->{LayoutObject}->Output(
                  TemplateFile => 'AgentZoomArticle',
                  Data => {%Param, %Article},
              );
            }
            $BodyOutput .= $Self->{LayoutObject}->Output(
                TemplateFile => 'AgentZoomBody', 
                Data => {%Param, %Article},
            );
        }
    }
    my $Output = $Self->{LayoutObject}->Output(
        TemplateFile => 'AgentZoomHead', 
        Data => \%Param, 
    );
    $Output .= $BodyOutput;
    $Output .= $Self->{LayoutObject}->Output(
        TemplateFile => 'AgentZoomFooter', 
        Data => \%Param,
    );
    # return output
    return $Output;
}
# --
sub MaskAgentZoomHTML {
    my $Self = shift;
    my %Param = @_;
    # generate output
    my $Output = "Content-Disposition: inline; filename=";
    $Output .= $Self->{ConfigObject}->Get('TicketHook')."-$Param{TicketNumber}-";
    $Output .= "$Param{TicketID}-$Param{ArticleID}\n";
    $Output .= "Content-Type: $Param{MimeType}; charset=$Param{ContentCharset}\n";
    $Output .= "\n";
    $Output .= $Param{"Body"};
    return $Output;
}
# --
1;
