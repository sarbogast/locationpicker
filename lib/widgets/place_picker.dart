import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:place_picker/entities/entities.dart';
import 'package:place_picker/widgets/widgets.dart';

import '../uuid.dart';

/// Place picker widget made with map widget from
/// [google_maps_flutter](https://github.com/flutter/plugins/tree/master/packages/google_maps_flutter)
/// and other API calls to [Google Places API](https://developers.google.com/places/web-service/intro)
///
/// API key provided should have `Maps SDK for Android`, `Maps SDK for iOS`
/// and `Places API`  enabled for it
class PlacePicker extends StatefulWidget {
  /// API key generated from Google Cloud Console. You can get an API key
  /// [here](https://cloud.google.com/maps-platform/)
  final String apiKey;

  /// Location to be displayed when screen is showed. If this is set or not null, the
  /// map does not pan to the user's current location.
  final LatLng displayLocation;

  final String nearbyPlacesLabel;
  final String findingPlaceLabel;
  final String noResultFoundLabel;
  final String tapToSelectThisLocationLabel;
  final String searchHint;
  final MapType mapType;
  final bool showNearbyPlaces;
  final BitmapDescriptor markerIcon;

  PlacePicker(
    this.apiKey, {
    this.displayLocation,
    this.nearbyPlacesLabel = 'Nearby Places',
    this.findingPlaceLabel = 'Finding place...',
    this.noResultFoundLabel = 'No result found',
    this.tapToSelectThisLocationLabel,
    this.searchHint,
    this.mapType = MapType.normal,
    this.showNearbyPlaces = true,
    this.markerIcon,
  });

  @override
  State<StatefulWidget> createState() => PlacePickerState();
}

/// Place picker state
class PlacePickerState extends State<PlacePicker> {
  final Completer<GoogleMapController> mapController = Completer();

  /// Indicator for the selected location
  final Set<Marker> markers = Set();

  /// Result returned after user completes selection
  LocationResult locationResult;

  /// Overlay to display autocomplete suggestions
  OverlayEntry overlayEntry;

  List<NearbyPlace> nearbyPlaces = List();

  /// Session token required for autocomplete API call
  String sessionToken = Uuid().generateV4();

  GlobalKey appBarKey = GlobalKey();

  bool hasSearchTerm = false;

  String previousSearchTerm = '';

  double _currentZoom;
  LatLng _currentLatLng;

  // constructor
  PlacePickerState();

  void onMapCreated(GoogleMapController controller) {
    this.mapController.complete(controller);
    moveToCurrentUserLocation();

    controller.getZoomLevel().then((value) => _currentZoom = value);
  }

  @override
  void setState(fn) {
    if (this.mounted) {
      super.setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _currentLatLng = widget.displayLocation;
    markers.add(Marker(
      icon: widget.markerIcon,
      position: widget.displayLocation ?? LatLng(5.6037, 0.1870),
      markerId: MarkerId("selected-location"),
    ));
  }

  @override
  void dispose() {
    this.overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        key: this.appBarKey,
        title: SearchInput(
          onSearchInput: searchPlace,
          searchHint: widget.searchHint,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: GoogleMap(
                mapType: widget.mapType,
                initialCameraPosition: CameraPosition(
                  target: widget.displayLocation ?? LatLng(5.6037, 0.1870),
                  zoom: 25,
                ),
                myLocationButtonEnabled: true,
                myLocationEnabled: true,
                onMapCreated: onMapCreated,
                onTap: (latLng) {
                  clearOverlay();
                  moveToLocation(latLng);
                },
                onCameraMove: (cameraPosition) {
                  _currentZoom = cameraPosition.zoom;
                  _currentLatLng = cameraPosition.target;
                  moveToLocation(
                    cameraPosition.target,
                    animated: false,
                    reverseGeocode: false,
                    updateNearbyPlaces: false,
                  );
                },
                onCameraIdle: () {
                  reverseGeocodeLatLng(_currentLatLng);
                  getNearbyPlaces(_currentLatLng);
                },
                markers: markers,
              ),
            ),
            SelectPlaceAction(
              locationName: getLocationName(),
              onTap: () => Navigator.of(context).pop(this.locationResult),
              tapToSelectThisLocationLabel: widget.tapToSelectThisLocationLabel,
            ),
            if (widget.showNearbyPlaces && !this.hasSearchTerm)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Divider(height: 8),
                    Padding(
                      child: Text(widget.nearbyPlacesLabel,
                          style: TextStyle(fontSize: 16)),
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    ),
                    Expanded(
                      child: ListView(
                        children: nearbyPlaces
                            .map(
                              (it) => NearbyPlaceItem(
                                it,
                                () => moveToLocation(it.latLng),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Hides the autocomplete overlay
  void clearOverlay() {
    if (this.overlayEntry != null) {
      this.overlayEntry.remove();
      this.overlayEntry = null;
    }
  }

  /// Begins the search process by displaying a "wait" overlay then
  /// proceeds to fetch the autocomplete list. The bottom "dialog"
  /// is hidden so as to give more room and better experience for the
  /// autocomplete list overlay.
  void searchPlace(String place) {
    // on keyboard dismissal, the search was being triggered again
    // this is to cap that.
    if (place == this.previousSearchTerm) {
      return;
    }

    previousSearchTerm = place;

    if (context == null) {
      return;
    }

    clearOverlay();

    setState(() {
      hasSearchTerm = place.length > 0;
    });

    if (place.length < 1) {
      return;
    }

    final RenderBox renderBox = context.findRenderObject();
    final size = renderBox.size;

    final RenderBox appBarBox =
        this.appBarKey.currentContext.findRenderObject();

    this.overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarBox.size.height,
        width: size.width,
        child: Material(
          elevation: 1,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: <Widget>[
                SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(width: 24),
                Expanded(
                    child: Text(widget.findingPlaceLabel,
                        style: TextStyle(fontSize: 16)))
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(this.overlayEntry);

    autoCompleteSearch(place);
  }

  /// Fetches the place autocomplete list with the query [place].
  void autoCompleteSearch(String place) async {
    try {
      place = place.replaceAll(" ", "+");

      var endpoint =
          "https://maps.googleapis.com/maps/api/place/autocomplete/json?" +
              "key=${widget.apiKey}&" +
              "input={$place}&sessiontoken=${this.sessionToken}";
      if (this.locationResult != null) {
        endpoint += "&location=${this.locationResult.latLng.latitude}," +
            "${this.locationResult.latLng.longitude}";
      }

      final response = await http.get(endpoint);

      if (response.statusCode != 200) {
        throw Error();
      }

      final responseJson = jsonDecode(response.body);

      if (responseJson['predictions'] == null) {
        throw Error();
      }

      List<dynamic> predictions = responseJson['predictions'];

      List<RichSuggestion> suggestions = [];

      if (predictions.isEmpty) {
        AutoCompleteItem aci = AutoCompleteItem();
        aci.text = widget.noResultFoundLabel;
        aci.offset = 0;
        aci.length = 0;

        suggestions.add(RichSuggestion(aci, () {}));
      } else {
        for (dynamic t in predictions) {
          final aci = AutoCompleteItem()
            ..id = t['place_id']
            ..text = t['description']
            ..offset = t['matched_substrings'][0]['offset']
            ..length = t['matched_substrings'][0]['length'];

          suggestions.add(RichSuggestion(aci, () {
            FocusScope.of(context).requestFocus(FocusNode());
            decodeAndSelectPlace(aci.id);
          }));
        }
      }

      displayAutoCompleteSuggestions(suggestions);
    } catch (e) {
      print(e);
    }
  }

  /// To navigate to the selected place from the autocomplete list to the map,
  /// the lat,lng is required. This method fetches the lat,lng of the place and
  /// proceeds to moving the map to that location.
  void decodeAndSelectPlace(String placeId) async {
    clearOverlay();

    try {
      final response = await http.get(
          "https://maps.googleapis.com/maps/api/place/details/json?key=${widget.apiKey}" +
              "&placeid=$placeId");

      if (response.statusCode != 200) {
        throw Error();
      }

      final responseJson = jsonDecode(response.body);

      if (responseJson['result'] == null) {
        throw Error();
      }

      final location = responseJson['result']['geometry']['location'];
      moveToLocation(LatLng(location['lat'], location['lng']));
    } catch (e) {
      print(e);
    }
  }

  /// Display autocomplete suggestions with the overlay.
  void displayAutoCompleteSuggestions(List<RichSuggestion> suggestions) {
    final RenderBox renderBox = context.findRenderObject();
    Size size = renderBox.size;

    final RenderBox appBarBox =
        this.appBarKey.currentContext.findRenderObject();

    clearOverlay();

    this.overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        top: appBarBox.size.height,
        child: Material(elevation: 1, child: Column(children: suggestions)),
      ),
    );

    Overlay.of(context).insert(this.overlayEntry);
  }

  /// Utility function to get clean readable name of a location. First checks
  /// for a human-readable name from the nearby list. This helps in the cases
  /// that the user selects from the nearby list (and expects to see that as a
  /// result, instead of road name). If no name is found from the nearby list,
  /// then the road name returned is used instead.
  String getLocationName() {
    if (this.locationResult == null) {
      return "Unnamed location";
    }

    for (NearbyPlace np in this.nearbyPlaces) {
      if (np.latLng == this.locationResult.latLng &&
          np.name != this.locationResult.locality) {
        this.locationResult.name = np.name;
        return "${np.name}, ${this.locationResult.locality}";
      }
    }

    return "${this.locationResult.name}, ${this.locationResult.locality}";
  }

  /// Moves the marker to the indicated lat,lng
  void setMarker(LatLng latLng) {
    // markers.clear();
    setState(() {
      markers.clear();
      markers.add(Marker(
        markerId: MarkerId("selected-location"),
        position: latLng,
        icon: widget.markerIcon,
      ));
    });
  }

  /// Fetches and updates the nearby places to the provided lat,lng
  void getNearbyPlaces(LatLng latLng) async {
    try {
      final response = await http.get(
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json?" +
              "key=${widget.apiKey}&" +
              "location=${latLng.latitude},${latLng.longitude}&radius=150");

      if (response.statusCode != 200) {
        throw Error();
      }

      final responseJson = jsonDecode(response.body);

      if (responseJson['results'] == null) {
        throw Error();
      }

      this.nearbyPlaces.clear();

      for (Map<String, dynamic> item in responseJson['results']) {
        final nearbyPlace = NearbyPlace()
          ..name = item['name']
          ..icon = item['icon']
          ..latLng = LatLng(item['geometry']['location']['lat'],
              item['geometry']['location']['lng']);

        this.nearbyPlaces.add(nearbyPlace);
      }

      // to update the nearby places
      setState(() {
        // this is to require the result to show
        this.hasSearchTerm = false;
      });
    } catch (e) {
      //
    }
  }

  /// This method gets the human readable name of the location. Mostly appears
  /// to be the road name and the locality.
  void reverseGeocodeLatLng(LatLng latLng) async {
    try {
      final response = await http.get(
          "https://maps.googleapis.com/maps/api/geocode/json?" +
              "latlng=${latLng.latitude},${latLng.longitude}&" +
              "key=${widget.apiKey}");

      if (response.statusCode != 200) {
        throw Error();
      }

      final responseJson = jsonDecode(response.body);

      if (responseJson['results'] == null) {
        throw Error();
      }

      if (responseJson['error_message'] != null) {
        print(responseJson['error_message']);
        throw Error();
      }

      if ((responseJson['results'] as List).isEmpty) {
        throw Error();
      }

      final result = responseJson['results'][0];

      setState(() {
        String name;
        AddressComponent country,
            city,
            postalCode,
            administrativeAreaLevel1,
            administrativeAreaLevel2,
            subLocalityLevel1,
            subLocalityLevel2;

        bool isOnStreet = false;
        if (result['address_components'] is List<dynamic> &&
            result['address_components'].length != null &&
            result['address_components'].length > 0) {
          for (var i = 0; i < result['address_components'].length; i++) {
            var tmp = result['address_components'][i];
            var types = tmp["types"] as List<dynamic>;
            var shortName = tmp['short_name'];
            var longName = tmp['long_name'];
            if (types == null) {
              continue;
            }
            if (i == 0) {
              // [street_number]
              name = shortName;
              isOnStreet = types.contains('street_number');
              // other index 0 types
              // [establishment, point_of_interest, subway_station, transit_station]
              // [premise]
              // [route]
            } else if (i == 1 && isOnStreet) {
              if (types.contains('route')) {
                name += ", $shortName";
              }
            }
            if (types.contains("sublocality_level_1")) {
              subLocalityLevel1 = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains("sublocality_level_2")) {
              subLocalityLevel2 = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains("locality")) {
              city = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains("administrative_area_level_2")) {
              administrativeAreaLevel2 = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains("administrative_area_level_1")) {
              administrativeAreaLevel1 = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains("country")) {
              country = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
            if (types.contains('postal_code')) {
              postalCode = AddressComponent(
                shortName: shortName,
                name: longName,
              );
            }
          }
        }
        this.locationResult = LocationResult()
          ..name = name
          ..latLng = latLng
          ..formattedAddress = result['formatted_address']
          ..placeId = result['place_id']
          ..postalCode = postalCode
          ..country = country
          ..administrativeAreaLevel1 = administrativeAreaLevel1
          ..administrativeAreaLevel2 = administrativeAreaLevel2
          ..city = city
          ..subLocalityLevel1 = subLocalityLevel1
          ..subLocalityLevel2 = subLocalityLevel2;
      });
    } catch (e) {
      print(e);
    }
  }

  /// Moves the camera to the provided location and updates other UI features to
  /// match the location.
  void moveToLocation(
    LatLng latLng, {
    bool animated = true,
    bool reverseGeocode = true,
    bool updateNearbyPlaces = true,
  }) {
    if (_currentZoom != null) {
      this.mapController.future.then((controller) {
        if (animated) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: latLng,
                zoom: _currentZoom,
              ),
            ),
          );
        } else {
          controller.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: latLng,
                zoom: _currentZoom,
              ),
            ),
          );
        }
      });
    } else {
      this.mapController.future.then((controller) {
        controller.getZoomLevel().then((currentZoomLevel) {
          if (animated) {
            controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: latLng,
                  zoom: currentZoomLevel,
                ),
              ),
            );
          } else {
            controller.moveCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: latLng,
                  zoom: currentZoomLevel,
                ),
              ),
            );
          }
        });
      });
    }

    setMarker(latLng);

    if (reverseGeocode) reverseGeocodeLatLng(latLng);

    if (updateNearbyPlaces) getNearbyPlaces(latLng);
  }

  void moveToCurrentUserLocation() {
    if (widget.displayLocation != null) {
      moveToLocation(widget.displayLocation);
      return;
    }

    Location().getLocation().then((locationData) {
      LatLng target = LatLng(locationData.latitude, locationData.longitude);
      _currentLatLng = target;
      moveToLocation(target);
    }).catchError((error) {
      // TODO: Handle the exception here
      print(error);
    });
  }
}
