import QtQuick 2.12
import QtCharts 2.3

import ThemeEngine 1.0
import "qrc:/js/UtilsNumber.js" as UtilsNumber

Item {
    id: itemAioLineCharts
    width: parent.width

    property bool showGraphDots: settingsManager.graphShowDots

    function loadGraph() {
        if (typeof currentDevice === "undefined" || !currentDevice) return
        //console.log("itemAioLineCharts // loadGraph() >> " + currentDevice)

        hygroData.visible = currentDevice.hasSoilMoistureSensor() && currentDevice.hasData("soilMoisture")
        conduData.visible = currentDevice.hasSoilConductivitySensor() && currentDevice.hasData("soilConductivity")
        tempData.visible = currentDevice.hasTemperatureSensor()
        hygroData.visible |= currentDevice.hasHumiditySensor() && currentDevice.hasData("humidity")
        lumiData.visible = currentDevice.hasLuminositySensor()

        dateIndicator.visible = false
        dataIndicator.visible = false
        verticalIndicator.visible = false
    }

    function updateGraph() {
        if (typeof currentDevice === "undefined" || !currentDevice) return
        //console.log("itemAioLineCharts // updateGraph() >> " + currentDevice)

        if (dateIndicator.visible) resetIndicator()

        var days = 14
        var count = currentDevice.countData("temperature", days)

        showGraphDots = (settingsManager.graphShowDots && count < 16)

        if (count > 1) {
            aioGraph.visible = true
            noDataIndicator.visible = false
        } else {
            aioGraph.visible = false
            noDataIndicator.visible = true
        }

        //// DATA
        hygroData.clear()
        conduData.clear()
        tempData.clear()
        lumiData.clear()

        currentDevice.getAioLinesData(days, axisTime, hygroData, conduData, tempData, lumiData);

        //// AXIS
        axisHygro.min = 0
        axisHygro.max = 100
        axisTemp.min = 0
        axisTemp.max = 60
        axisCondu.min = 0
        axisCondu.max = 2000
        axisLumi.min = 1
        axisLumi.max = 100000

        // Max axis for hygrometry
        if (currentDevice.hygroMax*1.15 > 100.0)
            axisHygro.max = 100.0; // no need to go higher than 100% soil moisture
        else
            axisHygro.max = currentDevice.hygroMax*1.15;

        // Max axis for temperature
        axisTemp.max = currentDevice.tempMax*1.15;

        // Max axis for conductivity
        axisCondu.max = currentDevice.conduMax*2.0;

        // Max axis for luminosity?
        axisLumi.max = currentDevice.luxMax*3.0;

        // Min axis computation, only for thermometers
        if (!currentDevice.hasSoilMoistureSensor()) {
            axisHygro.min = currentDevice.hygroMin*0.85;
            axisTemp.min = currentDevice.tempMin*0.85;
        }

        //// ADJUSTMENTS
        hygroData.width = 2
        tempData.width = 2

        if (currentDevice.deviceName === "ropot" || currentDevice.deviceName === "Parrot pot") {
            hygroData.width = 3 // Humidity is primary
        }

        if (!currentDevice.hasSoilMoistureSensor()) {
            tempData.width = 3 // Temperature is primary
        }

        if (currentDevice.deviceName === "Flower care" || currentDevice.deviceName === "Flower power") {
            // not planted? don't show hygro and condu
            hygroData.visible = currentDevice.hasSoilMoistureSensor() && currentDevice.hasData("soilMoisture")
            conduData.visible = currentDevice.hasSoilConductivitySensor() && currentDevice.hasData("soilConductivity")

            // Flower Care without hygro & conductivity data
            if (!hygroData.visible && !conduData.visible) {
                // Show luminosity and make temperature primary
                lumiData.visible = true
                tempData.width = 3

                // Luminosity can have min/max, cause values have a very wide range
                axisLumi.max = currentDevice.luxMax*1.5;
            } else {
                hygroData.width = 3 // Soil moisture is primary
            }
        }
    }

    function qpoint_lerp(p0, p1, x) { return (p0.y + (x - p0.x) * ((p1.y - p0.y) / (p1.x - p0.x))) }

    ////////////////////////////////////////////////////////////////////////////

    ChartView {
        id: aioGraph
        anchors.fill: parent
        anchors.margins: -20

        antialiasing: true
        legend.visible: false
        backgroundRoundness: 0
        backgroundColor: "transparent"
        animationOptions: ChartView.NoAnimation

        ValueAxis { id: axisHygro; visible: false; gridVisible: false; }
        ValueAxis { id: axisTemp; visible: false; gridVisible: false; }
        ValueAxis { id: axisLumi; visible: false; gridVisible: false; }
        ValueAxis { id: axisCondu; visible: false; gridVisible: false; }
        DateTimeAxis { id: axisTime; visible: true;
                       labelsFont.pixelSize: Theme.fontSizeContentSmall; labelsColor: Theme.colorText;
                       gridLineColor: Theme.colorSeparator; }

        LineSeries {
            id: lumiData
            pointsVisible: showGraphDots;
            color: Theme.colorYellow; width: 2;
            axisY: axisLumi; axisX: axisTime;
        }
        LineSeries {
            id: conduData
            pointsVisible: showGraphDots;
            color: Theme.colorRed; width: 2;
            axisY: axisCondu; axisX: axisTime;
        }
        LineSeries {
            id: tempData
            pointsVisible: showGraphDots;
            color: Theme.colorGreen; width: 2;
            axisY: axisTemp; axisX: axisTime;
        }
        LineSeries {
            id: hygroData
            pointsVisible: showGraphDots;
            color: Theme.colorBlue; width: 2;
            axisY: axisHygro; axisX: axisTime;
        }

        MouseArea {
            id: clickableGraphArea
            anchors.fill: aioGraph
/*
            onPositionChanged: {
                moveIndicator(mouse, true)
                mouse.accepted = true
            }
*/
            onClicked: {
                aioGraph.moveIndicator(mouse, false)
                mouse.accepted = true
            }
        }

        function moveIndicator(mouse, isMoving) {
            var mmm = Qt.point(mouse.x, mouse.y)

            // we adjust coordinates with graph area margins
            var ppp = Qt.point(mouse.x, mouse.y)
            ppp.x = ppp.x + aioGraph.anchors.rightMargin
            ppp.y = ppp.y - aioGraph.anchors.topMargin

            // map mouse position to graph value // mpmp.x is the timestamp
            var mpmp = aioGraph.mapToValue(mmm, tempData)

            //console.log("clicked " + mouse.x + " " + mouse.y)
            //console.log("clicked adjusted " + ppp.x + " " + ppp.y)
            //console.log("clicked mapped " + mpmp.x + " " + mpmp.y)

            if (isMoving) {
                // dragging outside the graph area?
                if (mpmp.x < tempData.at(0).x){
                    ppp.x = aioGraph.mapToPosition(tempData.at(0), tempData).x + aioGraph.anchors.rightMargin
                    mpmp.x = tempData.at(0).x
                }
                if (mpmp.x > tempData.at(tempData.count-1).x){
                    ppp.x = aioGraph.mapToPosition(tempData.at(tempData.count-1), tempData).x + aioGraph.anchors.rightMargin
                    mpmp.x = tempData.at(tempData.count-1).x
                }
            } else {
                // did we clicked outside the graph area?
                if (mpmp.x < tempData.at(0).x || mpmp.x > tempData.at(tempData.count-1).x) {
                    resetIndicator()
                    return
                }
            }

            // indicators is now visible
            dateIndicator.visible = true
            verticalIndicator.visible = true
            verticalIndicator.x = ppp.x

            // set date & time
            var date = new Date(mpmp.x)
            var date_string = date.toLocaleDateString()
            //: "at" is used for DATE at HOUR
            var time_string = qsTr("at") + " " + UtilsNumber.padNumber(date.getHours(), 2) + ":" + UtilsNumber.padNumber(date.getMinutes(), 2)
            textTime.text = date_string + " " + time_string

            // search index corresponding to the timestamp
            var x1 = -1
            var x2 = -1
            for (var i = 0; i < tempData.count; i++) {
                var graph_at_x = tempData.at(i).x
                var dist = (graph_at_x - mpmp.x) / 1000000

                if (Math.abs(dist) < 1) {
                    // nearest neighbor
                    if (appContent.state === "DevicePlantSensor") {
                        dataIndicators.updateDataBars(hygroData.at(i).y, conduData.at(i).y, -99,
                                                      tempData.at(i).y, -99, lumiData.at(i).y)
                    } else if (appContent.state === "DeviceThermometer") {
                        dataIndicator.visible = true
                        dataIndicatorText.text = (settingsManager.tempUnit === "F") ? UtilsNumber.tempCelsiusToFahrenheit(tempData.at(i).y).toFixed(1) + "°F" : tempData.at(i).y.toFixed(1) + "°C"
                        dataIndicatorText.text += " " + hygroData.at(i).y.toFixed(0) + "%"
                    }
                    break;
                } else {
                    if (dist < 0) {
                        if (x1 < i) x1 = i
                    } else {
                        x2 = i
                        break
                    }
                }
            }

            if (x1 >= 0 && x2 > x1) {
                // linear interpolation
                if (appContent.state === "DevicePlantSensor") {
                    dataIndicators.updateDataBars(qpoint_lerp(hygroData.at(x1), hygroData.at(x2), mpmp.x),
                                                  qpoint_lerp(conduData.at(x1), conduData.at(x2), mpmp.x),
                                                  -99,
                                                  qpoint_lerp(tempData.at(x1), tempData.at(x2), mpmp.x),
                                                  -99,
                                                  qpoint_lerp(lumiData.at(x1), lumiData.at(x2), mpmp.x))
                } else if (appContent.state === "DeviceThermometer") {
                    dataIndicator.visible = true
                    var temmp = qpoint_lerp(tempData.at(x1), tempData.at(x2), mpmp.x)
                    dataIndicatorText.text = (settingsManager.tempUnit === "F") ? UtilsNumber.tempCelsiusToFahrenheit(temmp).toFixed(1) + "°F" : temmp.toFixed(1) + "°C"
                    dataIndicatorText.text += " " + qpoint_lerp(hygroData.at(x1), hygroData.at(x2), mpmp.x).toFixed(0) + "%"
                }
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////

    ItemNoData {
        id: noDataIndicator
        anchors.fill: parent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        id: verticalIndicator
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28

        width: 2
        visible: false
        opacity: 0.66
        color: Theme.colorSubText

        Behavior on x { NumberAnimation { id: vanim; duration: 266; } }

        MouseArea {
            id: verticalIndicatorArea
            anchors.fill: parent
            anchors.margins: isMobile ? -24 : -8

            propagateComposedEvents: true
            hoverEnabled: false

            onReleased: {
                if (typeof (sensorPages) !== "undefined") sensorPages.interactive = isPhone
                vanim.duration = 266
            }
            onPositionChanged: {
                if (typeof (sensorPages) !== "undefined") {
                    // So we don't swipe pages as we drag the indicator
                    sensorPages.interactive = false
                }
                vanim.duration = 16

                var mouseMapped = mapToItem(clickableGraphArea, mouse.x, mouse.y)
                aioGraph.moveIndicator(mouseMapped, true)
                mouse.accepted = true
            }
        }

        onXChanged: {
            if (isPhone) return // verticalIndicator default to middle
            if (isTablet) return // verticalIndicator default to middle

            var direction = "middle"
            if (verticalIndicator.x > dateIndicator.width + 12)
                direction = "right"
            else if (itemAioLineCharts.width - verticalIndicator.x > dateIndicator.width + 12)
                direction = "left"

            if (direction === "middle") {
                // date indicator is too big, center on screen
                indicators.columns = 2
                indicators.rows = 1
                indicators.state = "reanchoredmid"
                indicators.layoutDirection = "LeftToRight"
            } else {
                // date indicator is positioned next to the vertical indicator
                indicators.columns = 1
                indicators.rows = 2
                if (direction === "left") {
                    indicators.state = "reanchoredleft"
                    indicators.layoutDirection = "LeftToRight"
                } else {
                    indicators.state = "reanchoredright"
                    indicators.layoutDirection = "RightToLeft"
                }
            }
        }
    }

    Grid {
        id: indicators
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter

        spacing: 12
        layoutDirection: "LeftToRight"
        columns: 2
        rows: 1

        transitions: Transition { AnchorAnimation { duration: 133; } }
        //move: Transition { NumberAnimation { properties: "x"; duration: 133; } }

        states: [
            State {
                name: "reanchoredmid"
                AnchorChanges {
                    target: indicators;
                    anchors.right: undefined;
                    anchors.left: undefined;
                    anchors.horizontalCenter: parent.horizontalCenter;
                }
            },
            State {
                name: "reanchoredleft"
                AnchorChanges {
                    target: indicators;
                    anchors.horizontalCenter: undefined;
                    anchors.right: undefined;
                    anchors.left: verticalIndicator.right;
                }
            },
            State {
                name: "reanchoredright"
                AnchorChanges {
                    target: indicators;
                    anchors.horizontalCenter: undefined;
                    anchors.left: undefined;
                    anchors.right: verticalIndicator.right;
                }
            }
        ]

        Rectangle {
            id: dateIndicator
            width: textTime.width + 16
            height: textTime.height + 16

            radius: 4
            visible: false
            color: Theme.colorForeground
            border.width: Theme.componentBorderWidth
            border.color: Theme.colorSeparator

            Text {
                id: textTime
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                font.pixelSize: (settingsManager.bigWidget && isMobile) ? 15 : 14
                font.bold: true
                color: Theme.colorSubText
            }
        }

        Rectangle {
            id: dataIndicator
            width: dataIndicatorText.width + 16
            height: dataIndicatorText.height + 16

            radius: 4
            visible: false
            color: Theme.colorForeground
            border.width: Theme.componentBorderWidth
            border.color: Theme.colorSeparator

            Text {
                id: dataIndicatorText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                font.pixelSize: (settingsManager.bigWidget && isMobile) ? 15 : 14
                font.bold: true
                color: Theme.colorSubText
            }
        }
    }

    MouseArea {
        anchors.fill: indicators
        anchors.margins: -8
        onClicked: resetIndicator()
    }

    onWidthChanged: resetIndicator()

    function isIndicator() {
        return verticalIndicator.visible
    }
    function resetIndicator() {
        dateIndicator.visible = false
        dataIndicator.visible = false
        verticalIndicator.visible = false

        if (typeof devicePlantSensorData === "undefined" || !devicePlantSensorData) return
        if (appContent.state === "DevicePlantSensor") dataIndicators.resetDataBars()
    }
}
