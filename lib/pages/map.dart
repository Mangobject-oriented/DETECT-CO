import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Firebase Realtime Database
import 'package:firebase_database/firebase_database.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class EvacSite {
  final String name;
  final String description;
  final String image;
  final LatLng location;

  EvacSite({
    required this.name,
    required this.description,
    required this.image,
    required this.location,
  });
}

// =====================================================
// HOSPITAL MODEL
// =====================================================

class Hospital {
  final String name;
  final String description;
  final LatLng location;

  Hospital({
    required this.name,
    required this.description,
    required this.location,
  });
}

class _MapTabState extends State<MapTab> {
  final mapController = MapController();

  LatLng? currentPosition;

  List<LatLng> routePoints = [];
  EvacSite? selectedSite;
  Hospital? selectedHospital;

  final LatLng swCorner =
      LatLng(14.13466576727542, 121.00698800147504);

  final LatLng neCorner =
      LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  final List<EvacSite> evacSites = [
    EvacSite(
      name: "Uwisan Brgy Hall Evacuation Site",
      description: "65PF+RC8, Looc Road, Calamba",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.23707209551028,
        121.17340069445697,
      ),
    ),
    EvacSite(
      name: "Lingga Elementary School",
      description: "658J+7WC, Dany, Calamba, 4027 Laguna",
      image: "assets/images/evac2.png",
      location: LatLng(
        14.215765305050551,
        121.18228271136698,
      ),
    ),
    EvacSite(
      name: "Palingon Elementary School",
      description:
          "658P+425, 202 Caballero St, Real, Calamba, 4027 Laguna",
      image: "assets/images/evac3.png",
      location: LatLng(
        14.215617735789499,
        121.1861596967596,
      ),
    ),

    // =====================================================
    // ADDITIONAL EVACUATION CENTERS FROM YOUR LIST
    // =====================================================

    EvacSite(
      name: "Evacuation Center 0",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.231580655616623,
        121.13694004166739,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 1",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.201319556660879,
        121.1320245730881,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 2",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.174504490904946,
        121.1087250140898,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 3",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.172963720486747,
        121.10557921410229,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 4",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.172113482744315,
        121.10432174218926,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 5",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.173410443862354,
        121.10617123123323,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 6",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.191485471680968,
        121.16396746679861,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 7",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.158661827191356,
        121.0630947146171,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 8",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.1606442315348,
        121.08255004753215,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 9",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.156989529900981,
        121.06391365513119,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 10",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.16775961272474,
        121.09698479793742,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 11",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.160582754167905,
        121.09950677838401,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 12",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.15923043180585,
        121.15055525970166,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 13",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.21619675699334,
        121.10831864742113,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 14",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.19776321566352,
        121.16026673606467,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 15",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.165501500947597,
        121.06344732444332,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 16",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.165737720981518,
        121.06336680143697,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 17",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.171235841465467,
        121.06845088677825,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 18",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.16468392333159,
        121.11166297009778,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 19",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.15841935848526,
        121.10292031938356,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 20",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.163877304381243,
        121.1193921217405,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 21",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.163682990151303,
        121.11221407903564,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 22",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.242245636596444,
        121.16112224477644,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 23",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.164067163693884,
        121.12022194425536,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 24",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.163974321171965,
        121.11967628696898,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 25",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.173841778034774,
        121.08997796950078,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 26",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.173532087184581,
        121.09044519284902,
      ),
    ),

    EvacSite(
      name: "Lamesa Elementary School",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.181175581767723,
        121.15693980811848,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 28",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.18134448099071,
        121.15551189061159,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 29",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.18116634694325,
        121.15527879277391,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 30",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.210171931261318,
        121.15006689273368,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 31",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.206790199579396,
        121.14534787891243,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 32",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.20831709925985,
        121.14122115513742,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 33",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.203316989780198,
        121.16152022776481,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 34",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.20293501289848,
        121.16351836432413,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 35",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.215706295566287,
        121.18229250422738,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 36",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.21500465075427,
        121.18263593884583,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 37",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.226867070119598,
        121.1791843408803,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 38",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.223606762143497,
        121.17913294369943,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 39",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.227311567599813,
        121.17801168719132,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 40",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.22685715333503,
        121.17931162113375,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 41",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.157609591385897,
        121.03890866929824,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 42",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.157611381431051,
        121.03837803346556,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 43",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.1577328195214,
        121.03865463924586,
      ),
    ),

    // #44 was not supplied

    EvacSite(
      name: "Evacuation Center 45",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.194772931406085,
        121.10653185321075,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 46",
      description: "Di sure",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.194675033800195,
        121.10681863228403,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 47",
      description: "Di sure wala picture",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.217662466254062,
        121.13031072145374,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 48",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.233286279876454,
        121.12109842224699,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 49",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.182311694818134,
        121.20046646919435,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 50",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.185232705776796,
        121.20302471896639,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 51",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.169150712852536,
        121.15392803071943,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 52",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.181345254262697,
        121.15550795406192,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 53",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.18117897378228,
        121.15693691953852,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 54",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.17255822267577,
        121.15257389020832,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 55",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.21128116910972,
        121.12683229027006,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 56",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.211349627395691,
        121.1274426826303,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 57",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.209635996811041,
        121.12946405931996,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 58",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.215181115082732,
        121.11838198577026,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 59",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.175734135330105,
        121.13707385200775,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 60",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.168667146420542,
        121.13890417103521,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 61",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.16942375060053,
        121.13784077220092,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 62",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.218842490643722,
        121.1338802227567,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 63",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.216682570976168,
        121.13684346719909,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 64",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.21561644928434,
        121.18616123969663,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 65",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.215038052466918,
        121.18625506138429,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 66",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.214198517822128,
        121.18481769796186,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 67",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.184056579877563,
        121.10727284773436,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 68",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.185505636435487,
        121.10514984241068,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 69",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.183889286377417,
        121.10469900997737,
      ),
    ),

    // #70 = Di mahanap, so no marker is added

    EvacSite(
      name: "Evacuation Center 71",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.180415280449884,
        121.17911049698672,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 72",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.179814627414459,
        121.1788240508865,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 73",
      description: "Di sure",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.181286443258058,
        121.18891086343608,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 74",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.180055211653634,
        121.18543688551486,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 75",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.179378280325913,
        121.183893714503,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 76",
      description: "Duplicate coordinate from supplied list",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.179378280325913,
        121.183893714503,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 77",
      description: "Duplicate coordinate from supplied list",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.179378280325913,
        121.183893714503,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 78",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.21515499619268,
        121.15170035378777,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 79",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.200979717555436,
        121.14041785088628,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 80",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.198048393372924,
        121.14038347822171,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 81",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.195537976854325,
        121.13676690730857,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 82",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.176778883054167,
        121.11816022580918,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 83",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.177911835403494,
        121.12109504450672,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 84",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.177816095642763,
        121.12040321215873,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 85",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.178159590514435,
        121.12114980633409,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 86",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.152360080307764,
        121.16213341703335,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 87",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.15250353343479,
        121.16224046555969,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 88",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.152406304744268,
        121.16264892494013,
      ),
    ),

    EvacSite(
      name: "Evacuation Center 89",
      description: "Supplied coordinate",
      image: "assets/images/evac1.png",
      location: LatLng(
        14.198555932678811,
        121.14916166968749,
      ),
    ),
  
  ];

  // =====================================================
  // HOSPITALS
  // =====================================================
  // TODO: replace name/description with the real hospital's
  // details, and add more entries as needed.

  final List<Hospital> hospitals = [
    Hospital(
      name: "Calamba Doctors' Hospital",
      description: "Calamba City, Laguna",
      location: LatLng(
        14.217318179834948,
        121.14191295757401,
      ),
    ),
    Hospital(
      name: "Calamba Medical Center",
      description: "Calamba City, Laguna",
      location: LatLng(
        14.206166437115906,
        121.15238771423762
      ),
    ),
    Hospital(
      name: "Gamez Hospital",
      description: "Calamba City, Laguna",
      location: LatLng(
        14.213035200419394,
        121.16425984193856
      ),
    ),
  ];

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  double waterLevel = 0;

  final DatabaseReference dbRef =
      FirebaseDatabase.instance.ref().child('flood');

  late final StreamSubscription<DatabaseEvent> _firebaseSub;

  @override
  void initState() {
    super.initState();

    _firebaseSub = dbRef.onValue.listen((event) {
      final data =
          event.snapshot.value as Map<dynamic, dynamic>?;

      if (data == null) return;

      final dynamic distanceRaw = data['distance'];

      final double value = distanceRaw is num
          ? distanceRaw.toDouble()
          : double.tryParse(distanceRaw.toString()) ?? 0;

      if (!mounted) return;

      setState(() {
        waterLevel = value;
      });
    });
  }

  @override
  void dispose() {
    _firebaseSub.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  // =====================================================
  // GET ROUTE
  // =====================================================

  Future<void> getRoute(
    LatLng start,
    LatLng end,
  ) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final coords =
            data['routes'][0]['geometry']['coordinates'];

        if (!mounted) return;

        setState(() {
          routePoints = coords
              .map<LatLng>(
                (c) => LatLng(c[1], c[0]),
              )
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Route API error: $e');
    }
  }

  // =====================================================
  // GO TO NEAREST EVACUATION SITE
  // =====================================================

  void _goToNearestEvac() {
    if (currentPosition == null) {
      _locateMe();
      return;
    }

    final Distance distance = Distance();

    EvacSite nearest = evacSites[0];
    double minDist = double.infinity;

    for (final site in evacSites) {
      final dist = distance.as(
        LengthUnit.Meter,
        currentPosition!,
        site.location,
      );

      if (dist < minDist) {
        minDist = dist;
        nearest = site;
      }
    }

    setState(() {
      selectedSite = nearest;
    });

    mapController.move(nearest.location, 16);

    getRoute(
      currentPosition!,
      nearest.location,
    );

    _showEvacPanel(nearest);
  }

  // =====================================================
  // GO TO NEAREST HOSPITAL
  // =====================================================

  void _goToNearestHospital() {
    if (currentPosition == null) {
      _locateMe();
      return;
    }

    final Distance distance = Distance();

    Hospital nearest = hospitals[0];
    double minDist = double.infinity;

    for (final hospital in hospitals) {
      final dist = distance.as(
        LengthUnit.Meter,
        currentPosition!,
        hospital.location,
      );

      if (dist < minDist) {
        minDist = dist;
        nearest = hospital;
      }
    }

    setState(() {
      selectedHospital = nearest;
    });

    mapController.move(nearest.location, 16);

    getRoute(
      currentPosition!,
      nearest.location,
    );

    _showHospitalPanel(nearest, minDist);
  }

  // =====================================================
  // EVACUATION SITE PANEL
  // =====================================================

  void _showEvacPanel(EvacSite site) {
    String riskText;
    Color riskColor;

    if (waterLevel > 40) {
      riskText = "SAFE";
      riskColor = const Color.fromRGBO(
        76,
        175,
        80,
        1,
      );
    } else if (waterLevel > 30) {
      riskText = "MEDIUM RISK";
      riskColor = Colors.orange;
    } else {
      riskText = "FLOODING";
      riskColor = const Color.fromRGBO(
        244,
        67,
        54,
        1,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height:
              MediaQuery.of(context).size.height * 0.50,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Image.asset(
                  site.image,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(site.description),

                      const SizedBox(height: 12),

                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              riskColor.withOpacity(0.15),
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                            color: riskColor,
                          ),
                        ),
                        child: Text(
                          "Flood Risk: $riskText",
                          style: TextStyle(
                            color: riskColor,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      const Spacer(),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (currentPosition != null) {
                              getRoute(
                                currentPosition!,
                                site.location,
                              );
                            }

                            mapController.move(
                              site.location,
                              16,
                            );

                            Navigator.pop(context);
                          },
                          icon: const Icon(
                            Icons.directions,
                          ),
                          label: const Text(
                            "Go to Location",
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (currentPosition != null) {
                              getRoute(
                                currentPosition!,
                                site.location,
                              );

                              mapController.move(
                                currentPosition!,
                                16,
                              );
                            }

                            Navigator.pop(context);
                          },
                          icon: const Icon(
                            Icons.navigation,
                          ),
                          label: const Text(
                            "Directions from Me",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // HOSPITAL PANEL
  // =====================================================

  void _showHospitalPanel(Hospital hospital, double distanceMeters) {
    final String distanceLabel = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km away'
        : '${distanceMeters.toStringAsFixed(0)} m away';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3035).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_hospital,
                      color: Color(0xFFFF3035),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hospital.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hospital.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue),
                ),
                child: Text(
                  distanceLabel,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (currentPosition != null) {
                      getRoute(currentPosition!, hospital.location);
                    }
                    mapController.move(hospital.location, 16);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.directions),
                  label: const Text("Go to Hospital"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // LEGEND ITEM
  // =====================================================

  Widget _legendItem(
    Color color,
    String text,
    bool isDarkMode,
  ) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 8),

        Text(
          text,
          style: TextStyle(
            color: isDarkMode
                ? Colors.white
                : Colors.black,
          ),
        ),
      ],
    );
  }

  // =====================================================
  // LOCATE USER
  // =====================================================

  Future<void> _locateMe() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint(
          'Location services are disabled.',
        );
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        debugPrint(
          'Location permission denied.',
        );
        return;
      }

      final pos =
          await Geolocator.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        currentPosition = LatLng(
          pos.latitude,
          pos.longitude,
        );

        followMe = true;
      });

      mapController.move(
        currentPosition!,
        16,
      );
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (
        context,
        isDarkMode,
        child,
      ) {
        return Scaffold(
          backgroundColor: isDarkMode
              ? const Color(0xFF212121)
              : Colors.white,

          body: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Container(
                color: isDarkMode
                    ? const Color(0xFF212121)
                    : const Color.fromARGB(
                        255,
                        72,
                        119,
                        247,
                      ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // LOGO

                        GestureDetector(
                          onDoubleTap: () {
                            isDarkModeNotifier.value =
                                !isDarkModeNotifier.value;
                          },
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Image.asset(
                              "assets/icon/detect-co_logo.png",
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // APP NAME

                        const Text(
                          'Map',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // MAP
              // =================================================

              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,

                      options: MapOptions(
                        initialCenter: calambaCenter,
                        initialZoom: 13.5,
                        cameraConstraint:
                            CameraConstraint.contain(
                          bounds: LatLngBounds(
                            swCorner,
                            neCorner,
                          ),
                        ),
                      ),

                      children: [
                        // =================================================
                        // OPENSTREETMAP TILES
                        // =================================================

                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName:
                              'com.detectco.app',
                        ),

                        // =================================================
                        // FLOOD ZONES
                        // =================================================

                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: LatLng(
                                14.234706315729172,
                                121.17367192746359,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.20)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
                              borderStrokeWidth: 2,
                            ),

                            CircleMarker(
                              point: LatLng(
                                14.209895867059025,
                                121.18097126019865,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.35)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
                              borderStrokeWidth: 2,
                            ),

                            CircleMarker(
                              point: LatLng(
                                14.215510239402107,
                                121.18530211042635,
                              ),
                              radius: 600,
                              useRadiusInMeter: true,
                              color: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    ).withOpacity(0.35)
                                  : waterLevel > 30
                                      ? Colors.orange
                                          .withOpacity(0.35)
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ).withOpacity(0.35),
                              borderColor: waterLevel > 40
                                  ? const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      1,
                                    )
                                  : waterLevel > 30
                                      ? Colors.orange
                                      : const Color.fromRGBO(
                                          244,
                                          67,
                                          54,
                                          1,
                                        ),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),

                        // =================================================
                        // ROUTE
                        // =================================================

                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 4,
                              color: const Color(0xFF4A7FF7),
                            ),
                          ],
                        ),

                        // =================================================
                        // MARKERS
                        // =================================================

                        MarkerLayer(
                          markers: [
                            if (currentPosition != null)
                              Marker(
                                point: currentPosition!,
                                width: 28,
                                height: 28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF4A7FF7),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            for (final site in evacSites)
                              Marker(
                                point: site.location,
                                width: 45,
                                height: 45,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showEvacPanel(site),
                                  child: Image.asset(
                                    'assets/icon/evacsite.png',
                                  ),
                                ),
                              ),

                            // ===== HOSPITAL MARKERS =====
                            for (final hospital in hospitals)
                              Marker(
                                point: hospital.location,
                                width: 44,
                                height: 44,
                                child: GestureDetector(
                                  onTap: () {
                                    final Distance distance = Distance();
                                    final double dist = currentPosition != null
                                        ? distance.as(
                                            LengthUnit.Meter,
                                            currentPosition!,
                                            hospital.location,
                                          )
                                        : 0;
                                    _showHospitalPanel(hospital, dist);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF3035),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black26, blurRadius: 4),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.local_hospital,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),

                    // =================================================
                    // GPS + NEAREST BUTTONS
                    // =================================================

                    Positioned(
                      top: 16,
                      right: 16,
                      child: Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'gps',
                            mini: true,
                            backgroundColor:
                                const Color.fromARGB(
                              255,
                              245,
                              245,
                              245,
                            ),
                            onPressed: _locateMe,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                            ),
                          ),

                          const SizedBox(height: 10),

                          FloatingActionButton(
                            heroTag: 'nearest',
                            mini: true,
                            backgroundColor:
                                const Color.fromARGB(
                              255,
                              129,
                              160,
                              247,
                            ),
                            onPressed:
                                _goToNearestEvac,
                            child: const Icon(
                              Icons.place,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 10),

                          // ===== NEAREST HOSPITAL BUTTON =====
                          FloatingActionButton(
                            heroTag: 'nearest_hospital',
                            mini: true,
                            backgroundColor: const Color(0xFFFF3035),
                            onPressed: _goToNearestHospital,
                            child: const Icon(
                              Icons.local_hospital,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // =================================================
                    // LEGEND
                    // =================================================

                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding:
                            const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2C2C2C)
                                  .withOpacity(0.92)
                              : Colors.white
                                  .withOpacity(0.92),
                          borderRadius:
                              BorderRadius.circular(14),
                          boxShadow: [        
                            BoxShadow(
                              color: isDarkMode
                                  ? Colors.black54
                                  : Colors.black26,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _legendItem(
                              Colors.green,
                              "Safe",
                              isDarkMode,
                            ),

                            const SizedBox(height: 6),

                            _legendItem(
                              Colors.orange,
                              "Medium Risk",
                              isDarkMode,
                            ),

                            const SizedBox(height: 6),

                            _legendItem(
                              Colors.red,
                              "Flooding",
                              isDarkMode,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}