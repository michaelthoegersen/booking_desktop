import 'package:latlong2/latlong.dart';

String _n(String s) => s.trim().toLowerCase();

final Map<String, LatLng> cityCoords = {

  // ===================== NORWAY =====================

  _n('Oslo'): LatLng(59.9139, 10.7522),
  _n('Bergen'): LatLng(60.3913, 5.3221),
  _n('Trondheim'): LatLng(63.4305, 10.3951),
  _n('Stavanger'): LatLng(58.9700, 5.7331),
  _n('Kristiansand'): LatLng(58.1467, 7.9956),
  _n('Drammen'): LatLng(59.7439, 10.2045),
  _n('Fredrikstad'): LatLng(59.2181, 10.9298),
  _n('Sarpsborg'): LatLng(59.2839, 11.1096),
  _n('Moss'): LatLng(59.4584, 10.7001),
  _n('Halden'): LatLng(59.1248, 11.3875),
  _n('Skien'): LatLng(59.2090, 9.6020),
  _n('Porsgrunn'): LatLng(59.1386, 9.6520),
  _n('Tønsberg'): LatLng(59.2675, 10.4074),
  _n('Sandefjord'): LatLng(59.1314, 10.2166),
  _n('Larvik'): LatLng(59.0533, 10.0352),
  _n('Horten'): LatLng(59.4170, 10.4834),

  _n('Haugesund'): LatLng(59.4138, 5.2680),
  _n('Stord'): LatLng(59.7809, 5.5005),
  _n('Leirvik'): LatLng(59.7798, 5.4983),

  _n('Ålesund'): LatLng(62.4722, 6.1495),
  _n('Molde'): LatLng(62.7370, 7.1607),
  _n('Kristiansund'): LatLng(63.1115, 7.7320),
  _n('Volda'): LatLng(62.1483, 6.0687),
  _n('Ulsteinvik'): LatLng(62.3434, 5.8477),

  _n('Bodø'): LatLng(67.2804, 14.4049),
  _n('Mo i Rana'): LatLng(66.3128, 14.1428),
  _n('Mosjøen'): LatLng(65.8366, 13.1907),
  _n('Brønnøysund'): LatLng(65.4741, 12.2126),

  _n('Tromsø'): LatLng(69.6492, 18.9553),
  _n('Alta'): LatLng(69.9689, 23.2717),
  _n('Hammerfest'): LatLng(70.6610, 23.6821),
  _n('Narvik'): LatLng(68.4384, 17.4272),
  _n('Harstad'): LatLng(68.7983, 16.5417),
  _n('Finnsnes'): LatLng(69.2296, 17.9814),

  _n('Hamar'): LatLng(60.7945, 11.0679),
  _n('Lillehammer'): LatLng(61.1153, 10.4662),
  _n('Gjøvik'): LatLng(60.7957, 10.6916),
  _n('Elverum'): LatLng(60.8823, 11.5623),
  _n('Kongsvinger'): LatLng(60.1870, 11.9977),

  _n('Røros'): LatLng(62.5748, 11.3843),
  _n('Steinkjer'): LatLng(64.0139, 11.4954),
  _n('Verdal'): LatLng(63.7931, 11.4814),
  _n('Levanger'): LatLng(63.7464, 11.2996),

  _n('Arendal'): LatLng(58.4616, 8.7723),
  _n('Grimstad'): LatLng(58.3405, 8.5934),
  _n('Mandal'): LatLng(58.0270, 7.4530),
  _n('Farsund'): LatLng(58.0948, 6.8046),
  _n('Flekkefjord'): LatLng(58.2974, 6.6631),

  _n('Notodden'): LatLng(59.5593, 9.2584),
  _n('Rjukan'): LatLng(59.8785, 8.5941),

  _n('Sogndal'): LatLng(61.2316, 7.1030),
  _n('Førde'): LatLng(61.4516, 5.8572),
  _n('Florø'): LatLng(61.5996, 5.0325),

  _n('Voss'): LatLng(60.6280, 6.4147),
  _n('Odda'): LatLng(60.0691, 6.5456),

  _n('Askøy'): LatLng(60.4019, 5.2480),
  _n('Knarvik'): LatLng(60.5451, 5.2831),

  _n('Kongsberg'): LatLng(59.6693, 9.6502),
  _n('Hønefoss'): LatLng(60.1680, 10.2565),

  _n('Ski'): LatLng(59.7191, 10.8353),
  _n('Lillestrøm'): LatLng(59.9553, 11.0492),
  _n('Jessheim'): LatLng(60.1415, 11.1741),

  _n('Stjørdal'): LatLng(63.4685, 10.9255),
  _n('Melhus'): LatLng(63.2876, 10.2762),

  _n('Åndalsnes'): LatLng(62.5674, 7.6873),
  _n('Sunndalsøra'): LatLng(62.6751, 8.5635),

  _n('Kirkenes'): LatLng(69.7250, 30.0450),
  _n('Vadsø'): LatLng(70.0745, 29.7604),
  _n('Vardø'): LatLng(70.3705, 31.1107),

  // ===================== SWEDEN =====================

  _n('Stockholm'): LatLng(59.3293, 18.0686),
  _n('Solna'): LatLng(59.3600, 18.0009),
  _n('Sundbyberg'): LatLng(59.3613, 17.9714),
  _n('Sollentuna'): LatLng(59.4280, 17.9509),
  _n('Täby'): LatLng(59.4439, 18.0687),
  _n('Nacka'): LatLng(59.3108, 18.1635),
  _n('Huddinge'): LatLng(59.2365, 17.9819),
  _n('Botkyrka'): LatLng(59.1995, 17.8331),
  _n('Tyresö'): LatLng(59.2422, 18.2986),

  _n('Göteborg'): LatLng(57.7089, 11.9746),
  _n('Mölndal'): LatLng(57.6554, 12.0138),
  _n('Partille'): LatLng(57.7390, 12.1067),
  _n('Kungälv'): LatLng(57.8716, 11.9805),
  _n('Alingsås'): LatLng(57.9303, 12.5334),
  _n('Lerum'): LatLng(57.7705, 12.2697),

  _n('Malmö'): LatLng(55.6050, 13.0038),
  _n('Lund'): LatLng(55.7047, 13.1910),
  _n('Helsingborg'): LatLng(56.0465, 12.6945),
  _n('Landskrona'): LatLng(55.8708, 12.8302),
  _n('Trelleborg'): LatLng(55.3751, 13.1569),
  _n('Ystad'): LatLng(55.4295, 13.8204),
  _n('Ängelholm'): LatLng(56.2428, 12.8622),
  _n('Höganäs'): LatLng(56.1997, 12.5577),

  _n('Uppsala'): LatLng(59.8586, 17.6389),
  _n('Enköping'): LatLng(59.6361, 17.0777),
  _n('Knivsta'): LatLng(59.7257, 17.7865),

  _n('Västerås'): LatLng(59.6099, 16.5448),
  _n('Eskilstuna'): LatLng(59.3717, 16.5099),
  _n('Köping'): LatLng(59.5141, 15.9926),
  _n('Arboga'): LatLng(59.3939, 15.8380),

  _n('Örebro'): LatLng(59.2753, 15.2134),
  _n('Karlskoga'): LatLng(59.3267, 14.5239),
  _n('Kumla'): LatLng(59.1277, 15.1434),
  _n('Hallsberg'): LatLng(59.0652, 15.1106),

  _n('Linköping'): LatLng(58.4108, 15.6214),
  _n('Norrköping'): LatLng(58.5877, 16.1924),
  _n('Motala'): LatLng(58.5371, 15.0365),
  _n('Mjölby'): LatLng(58.3259, 15.1236),
  _n('Finspång'): LatLng(58.7056, 15.7744),

  _n('Jönköping'): LatLng(57.7826, 14.1618),
  _n('Huskvarna'): LatLng(57.7866, 14.3023),
  _n('Värnamo'): LatLng(57.1860, 14.0415),
  _n('Nässjö'): LatLng(57.6530, 14.6968),

  _n('Borås'): LatLng(57.7210, 12.9401),
  _n('Ulricehamn'): LatLng(57.7916, 13.4137),
  _n('Tranemo'): LatLng(57.4831, 13.3504),

  _n('Halmstad'): LatLng(56.6745, 12.8578),
  _n('Varberg'): LatLng(57.1056, 12.2508),
  _n('Falkenberg'): LatLng(56.9027, 12.4912),
  _n('Laholm'): LatLng(56.5126, 13.0435),

  _n('Växjö'): LatLng(56.8777, 14.8091),
  _n('Alvesta'): LatLng(56.8995, 14.5567),
  _n('Ljungby'): LatLng(56.8325, 13.9410),

  _n('Kalmar'): LatLng(56.6634, 16.3568),
  _n('Oskarshamn'): LatLng(57.2650, 16.4485),
  _n('Västervik'): LatLng(57.7584, 16.6373),

  _n('Karlstad'): LatLng(59.3791, 13.5041),
  _n('Kristinehamn'): LatLng(59.3090, 14.1085),
  _n('Arvika'): LatLng(59.6542, 12.5914),
  _n('Säffle'): LatLng(59.1336, 12.9283),

  _n('Falun'): LatLng(60.6036, 15.6259),
  _n('Borlänge'): LatLng(60.4843, 15.4371),
  _n('Avesta'): LatLng(60.1457, 16.1684),
  _n('Ludvika'): LatLng(60.1496, 15.1875),

  _n('Gävle'): LatLng(60.6745, 17.1417),
  _n('Sandviken'): LatLng(60.6200, 16.7754),
  _n('Hudiksvall'): LatLng(61.7281, 17.1056),

  _n('Sundsvall'): LatLng(62.3908, 17.3069),
  _n('Timrå'): LatLng(62.4872, 17.3264),
  _n('Härnösand'): LatLng(62.6360, 17.9410),
  _n('Kramfors'): LatLng(62.9316, 17.7765),

  _n('Östersund'): LatLng(63.1792, 14.6357),
  _n('Åre'): LatLng(63.3987, 13.0812),

  _n('Umeå'): LatLng(63.8258, 20.2630),
  _n('Skellefteå'): LatLng(64.7507, 20.9528),
  _n('Lycksele'): LatLng(64.5954, 18.6735),

  _n('Luleå'): LatLng(65.5848, 22.1547),
  _n('Piteå'): LatLng(65.3172, 21.4790),
  _n('Boden'): LatLng(65.8252, 21.6886),

  _n('Kiruna'): LatLng(67.8558, 20.2253),
  _n('Gällivare'): LatLng(67.1339, 20.6528),
  _n('Haparanda'): LatLng(65.8355, 24.1377),

  _n('Visby'): LatLng(57.6348, 18.2948),

  // ===================== DENMARK =====================

  _n('Copenhagen'): LatLng(55.6761, 12.5683),
  _n('Aarhus'): LatLng(56.1629, 10.2039),
  _n('Odense'): LatLng(55.4038, 10.4024),
  _n('Aalborg'): LatLng(57.0488, 9.9217),
};