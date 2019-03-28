# 
#  Copyright 2006 - 2010 Unified EFI, Inc.<BR> 
#  Copyright (c) 2010, Intel Corporation. All rights reserved.<BR>
# 
#  This program and the accompanying materials
#  are licensed and made available under the terms and conditions of the BSD License
#  which accompanies this distribution.  The full text of the license may be found at 
#  http://opensource.org/licenses/bsd-license.php
# 
#  THE PROGRAM IS DISTRIBUTED UNDER THE BSD LICENSE ON AN "AS IS" BASIS,
#  WITHOUT WARRANTIES OR REPRESENTATIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED.
# 
################################################################################
CaseLevel         FUNCTION
CaseAttribute     AUTO
CaseVerboseLevel  DEFAULT 
set reportfile    report.csv

#
# test case Name, category, description, GUID...
#
CaseGuid        28644F9B-18AC-420b-9100-D8E4AD8F8852
CaseName        Routes.Func1.Case1
CaseCategory    Udp4
CaseDescription {Test the Routes Function of UDP4 - Invoke Routes() to add a   \
                 route to destination IP and send a packet to it.}
################################################################################

Include UDP4/include/Udp4.inc.tcl

proc CleanUpEutEnvironment {} {
  DelEntryInArpCache
  BS->CloseEvent "@R_Token.Event, &@R_Status"
  GetAck
  
  Udp4ServiceBinding->DestroyChild {@R_Handle, &@R_Status}
  GetAck

  EndCapture
  
  VifDown 0
  
  EndScope _UDP4_ROUTES_FUNCTION1_CASE1_
  
  EndLog
}

#
# Begin log ...
#
BeginLog

#
# End scope
#
BeginScope _UDP4_ROUTES_FUNCTION1_CASE1_

set hostmac              [GetHostMac]
set targetmac            [GetTargetMac]
set targetip             192.168.88.1
set hostip               192.168.88.2
set subnetmask           255.255.255.0
set targetport           4000
set hostport             4000
set arg_destaddrss       172.16.220.3
set arg_subnetaddrss     172.16.220.0
set arg_subnetmask       $subnetmask
set arg_gatewayaddress   $hostip

VifUp 0 $hostip

#
# Parameter Definition
# R_ represents "Remote EFI Side Parameter"
# L_ represents "Local OS Side Parameter"
#
UINTN                            R_Status
UINTN                            R_Handle
EFI_UDP4_CONFIG_DATA             R_Udp4ConfigData
UINTN                            R_Context
EFI_UDP4_COMPLETION_TOKEN        R_Token
EFI_IPv4_ADDRESS                 SubnetAddress
EFI_IPv4_ADDRESS                 SubnetMask
EFI_IPv4_ADDRESS                 GatewayAddress
EFI_UDP4_TRANSMIT_DATA           R_TxData
EFI_UDP4_FRAGMENT_DATA           R_FragmentTable
CHAR8                            R_FragmentBuffer(600)

#
# Add an entry in ARP cache.
#
AddEntryInArpCache

Udp4ServiceBinding->CreateChild "&@R_Handle, &@R_Status"
GetAck
SetVar   [subst $ENTS_CUR_CHILD]  @R_Handle
set assert [VerifyReturnStatus R_Status $EFI_SUCCESS]
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4SBP.Routes - Func - Create Child"                         \
                "ReturnStatus - $R_Status, ExpectedStatus - $EFI_SUCCESS"

SetVar R_Udp4ConfigData.AcceptBroadcast             TRUE
SetVar R_Udp4ConfigData.AcceptPromiscuous           FALSE
SetVar R_Udp4ConfigData.AcceptAnyPort               TRUE
SetVar R_Udp4ConfigData.AllowDuplicatePort          TRUE
SetVar R_Udp4ConfigData.TypeOfService               0
SetVar R_Udp4ConfigData.TimeToLive                  1
SetVar R_Udp4ConfigData.DoNotFragment               TRUE
SetVar R_Udp4ConfigData.ReceiveTimeout              0
SetVar R_Udp4ConfigData.TransmitTimeout             0
SetVar R_Udp4ConfigData.UseDefaultAddress           FALSE
SetIpv4Address R_Udp4ConfigData.StationAddress      $targetip
SetIpv4Address R_Udp4ConfigData.SubnetMask          $subnetmask
SetVar R_Udp4ConfigData.StationPort                 $targetport
SetIpv4Address R_Udp4ConfigData.RemoteAddress       $arg_destaddrss
SetVar R_Udp4ConfigData.RemotePort                  $hostport

#
# check point
#
Udp4->Configure {&@R_Udp4ConfigData, &@R_Status}
GetAck
set assert [VerifyReturnStatus R_Status $EFI_SUCCESS]
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - Config Child"                            \
                "ReturnStatus - $R_Status, ExpectedStatus - $EFI_SUCCESS"

BS->CreateEvent "$EVT_NOTIFY_SIGNAL, $EFI_TPL_CALLBACK, 1, &@R_Context,        \
                 &@R_Token.Event, &@R_Status"
GetAck

#
# Add route to $arg_destaddrss
#
SetIpv4Address SubnetAddress  $arg_subnetaddrss
SetIpv4Address SubnetMask     $arg_subnetmask
SetIpv4Address GatewayAddress $arg_gatewayaddress

Udp4->Routes {FALSE, &@SubnetAddress, &@SubnetMask, &@GatewayAddress, &@R_Status}
GetAck
set assert [VerifyReturnStatus R_Status $EFI_SUCCESS]
RecordAssertion $assert $Udp4RoutesFunc1AssertionGuid001                       \
                "Udp4.Routes - Func - Add route with GatewayAddress            \
                 arg_gatewayaddress"                                           \
                "ReturnStatus - $R_Status, ExpectedStatus - $EFI_SUCCESS"

SetVar R_TxData.DataLength      20
SetVar R_TxData.FragmentCount   1
SetVar R_TxData.UdpSessionData  0 
SetVar R_TxData.GatewayAddress  0

SetVar R_FragmentBuffer                 "UdpConfigureTest" 
SetVar R_FragmentTable.FragmentBuffer   &@R_FragmentBuffer
SetVar R_FragmentTable.FragmentLength   20
SetVar R_TxData.FragmentTable           @R_FragmentTable
SetVar R_Token.Packet                   &@R_TxData

set L_Filter "udp port $targetport"
StartCapture CCB $L_Filter

Udp4->Transmit {&@R_Token, &@R_Status}

ReceiveCcbPacket CCB TempPacket 10

if { ${CCB.received} == 0} {
  #
  # If have not captured the packet. Fail
  #
  GetAck
  GetVar R_Status
  GetVar R_Token.Status
  set assert fail
  RecordAssertion $assert $GenericAssertionGuid                                \
                  "Udp4.Routes - Func - Transmit a packet"                     \
                  "Packet not captured, R_Status - $R_Status,                  \
                   R_Token.Status - ${R_Token.Status}"

  CleanUpEutEnvironment
  
  return
}

#
# If have captured the packet.
#
GetAck
set assert [VerifyReturnStatus R_Status $EFI_SUCCESS]
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - Transmit a packet"                       \
                "ReturnStatus - $R_Status, ExpectedStatus - $EFI_SUCCESS"

#
# Verify R_Token.Status
#
GetVar R_Token.Status
if {${R_Token.Status} == $EFI_SUCCESS} {
  set assert pass
} else {
  set assert fail
}
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - Check R_Token.Status"                    \
                "ReturnStatus - ${R_Token.Status}, ExpectedStatus - $EFI_SUCCESS"

#
# Verify the Event
#
GetVar R_Context
if {$R_Context == 1} {
  set assert pass
} else {
  set assert fail
}
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - check Event"                             \
                "Return R_Context - $R_Context, Expected R_Context - 1"

#
# Verify the eth header in the packet
#
if {[ValidatePacket	TempPacket -t eth (eth_src=$targetmac)AND(eth_dst=$hostmac)]== 0 } {
  set assert pass
} else {
  set assert fail
}	
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - check the packet's eth header"           \
                "Expected Source MAC - $targetmac; Expected Dest MAC - $hostmac"


#
# Verify the IP header in the packet
#
if {[ValidatePacket TempPacket -t ip (ipv4_src=$targetip)AND(ipv4_dst=$arg_destaddrss)]== 0 } {
  set assert pass
} else {
  set assert fail
}
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - check the packet's IP header"            \
                "Expected Source IP - $targetip; Expected Dest IP - $arg_destaddrss"

#
# Verify the UDP header in the packet
#
if {[ValidatePacket TempPacket -t udp (udp_sp=$targetport)AND(udp_dp=$hostport)] == 0 } {
  set assert pass
} else {
  set assert fail
}
RecordAssertion $assert $GenericAssertionGuid                                  \
                "Udp4.Routes - Func - check the packet's UDP header"           \
                "Expected Source Port - $targetport; Expected Dest Port - $hostport"

CleanUpEutEnvironment