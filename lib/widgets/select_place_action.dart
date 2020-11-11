import 'package:flutter/material.dart';

class SelectPlaceAction extends StatelessWidget {
  final String locationName;
  final VoidCallback onTap;
  final String tapToSelectThisLocationLabel;

  SelectPlaceAction({
    this.locationName,
    this.onTap,
    this.tapToSelectThisLocationLabel = 'Tap to select this location',
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(locationName, style: TextStyle(fontSize: 16)),
                    Text(tapToSelectThisLocationLabel,
                        style: TextStyle(color: Colors.grey, fontSize: 15)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward)
            ],
          ),
        ),
      ),
    );
  }
}
