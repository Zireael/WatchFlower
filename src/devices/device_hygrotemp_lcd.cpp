/*!
 * This file is part of WatchFlower.
 * COPYRIGHT (C) 2020 Emeric Grange - All Rights Reserved
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * \date      2018
 * \author    Emeric Grange <emeric.grange@gmail.com>
 */

#include "device_hygrotemp_lcd.h"
#include "utils/utils_versionchecker.h"

#include <cstdint>
#include <cmath>

#include <QBluetoothUuid>
#include <QBluetoothAddress>
#include <QBluetoothServiceInfo>
#include <QLowEnergyService>

#include <QSqlQuery>
#include <QSqlError>

#include <QDebug>

/* ************************************************************************** */

DeviceHygrotempLCD::DeviceHygrotempLCD(QString &deviceAddr, QString &deviceName, QObject *parent):
    DeviceSensor(deviceAddr, deviceName, parent)
{
    m_deviceType = DEVICE_THERMOMETER;
    m_deviceSensors += DEVICE_TEMPERATURE;
    m_deviceSensors += DEVICE_HUMIDITY;
}

DeviceHygrotempLCD::DeviceHygrotempLCD(const QBluetoothDeviceInfo &d, QObject *parent):
    DeviceSensor(d, parent)
{
    m_deviceType = DEVICE_THERMOMETER;
    m_deviceSensors += DEVICE_TEMPERATURE;
    m_deviceSensors += DEVICE_HUMIDITY;
}

DeviceHygrotempLCD::~DeviceHygrotempLCD()
{
    delete serviceData;
    delete serviceBattery;
    delete serviceInfos;
}

/* ************************************************************************** */
/* ************************************************************************** */

void DeviceHygrotempLCD::serviceScanDone()
{
    //qDebug() << "DeviceHygrotempLCD::serviceScanDone(" << m_deviceAddress << ")";

    if (serviceInfos)
    {
        if (serviceInfos->state() == QLowEnergyService::DiscoveryRequired)
        {
            connect(serviceInfos, &QLowEnergyService::stateChanged, this, &DeviceHygrotempLCD::serviceDetailsDiscovered_infos); // custom

            // Windows hack, see: QTBUG-80770 and QTBUG-78488
            QTimer::singleShot(0, this, [=] () { serviceInfos->discoverDetails(); });
        }
    }

    if (serviceBattery)
    {
        if (serviceBattery->state() == QLowEnergyService::DiscoveryRequired)
        {
            connect(serviceBattery, &QLowEnergyService::stateChanged, this, &DeviceHygrotempLCD::serviceDetailsDiscovered_battery);

            // Windows hack, see: QTBUG-80770 and QTBUG-78488
            QTimer::singleShot(0, this, [=] () { serviceBattery->discoverDetails(); });
        }
    }

    if (serviceData)
    {
        if (serviceData->state() == QLowEnergyService::DiscoveryRequired)
        {
            connect(serviceData, &QLowEnergyService::stateChanged, this, &DeviceHygrotempLCD::serviceDetailsDiscovered_data);
            connect(serviceData, &QLowEnergyService::characteristicChanged, this, &DeviceHygrotempLCD::bleReadNotify);

            // Windows hack, see: QTBUG-80770 and QTBUG-78488
            QTimer::singleShot(0, this, [=] () { serviceData->discoverDetails(); });
        }
    }
}

/* ************************************************************************** */

void DeviceHygrotempLCD::addLowEnergyService(const QBluetoothUuid &uuid)
{
    //qDebug() << "DeviceHygrotempLCD::addLowEnergyService(" << uuid.toString() << ")";

    if (uuid.toString() == "{0000180a-0000-1000-8000-00805f9b34fb}") // infos
    {
        delete serviceInfos;
        serviceInfos = nullptr;

        if (m_firmware.isEmpty() || m_firmware == "UNKN")
        {
            serviceInfos = controller->createServiceObject(uuid);
            if (!serviceInfos)
                qWarning() << "Cannot create service (infos) for uuid:" << uuid.toString();
        }
    }
/*
    if (uuid.toString() == "{0000180f-0000-1000-8000-00805f9b34fb}") // (unknown service) // battery
    {
        m_capabilities += DEVICE_BATTERY;
        Q_EMIT statusUpdated();

        delete serviceBattery;
        serviceBattery = nullptr;

        serviceBattery = controller->createServiceObject(uuid);
        if (!serviceBattery)
            qWarning() << "Cannot create service (battery) for uuid:" << uuid.toString();
    }
*/
    if (uuid.toString() == "{226c0000-6476-4566-7562-66734470666d}") // (unknown service) // data
    {
        delete serviceData;
        serviceData = nullptr;

        serviceData = controller->createServiceObject(uuid);
        if (!serviceData)
            qWarning() << "Cannot create service (data) for uuid:" << uuid.toString();
    }
}

/* ************************************************************************** */

void DeviceHygrotempLCD::serviceDetailsDiscovered_infos(QLowEnergyService::ServiceState newState)
{
    if (newState == QLowEnergyService::ServiceDiscovered)
    {
        //qDebug() << "DeviceHygrotempLCD::serviceDetailsDiscovered_infos(" << m_deviceAddress << ") > ServiceDiscovered";

        // Characteristic "Firmware Revision String"
        QBluetoothUuid c(QString("00002a26-0000-1000-8000-00805f9b34fb")); // handler 0x19
        QLowEnergyCharacteristic chc = serviceInfos->characteristic(c);
        if (chc.value().size() > 0)
        {
           m_firmware = chc.value();
        }

        if (m_firmware.size() == 8)
        {
            if (Version(m_firmware) >= Version(LATEST_KNOWN_FIRMWARE_HYGROTEMP_LCD))
            {
                m_firmware_uptodate = true;
                Q_EMIT sensorUpdated();
            }
        }
    }
}

void DeviceHygrotempLCD::serviceDetailsDiscovered_battery(QLowEnergyService::ServiceState newState)
{
    if (newState == QLowEnergyService::ServiceDiscovered)
    {
        //qDebug() << "DeviceHygrotempLCD::serviceDetailsDiscovered_battery(" << m_deviceAddress << ") > ServiceDiscovered";
/*
        if (serviceBattery)
        {
            // Characteristic "?"
            QBluetoothUuid b(QString("00002a19-0000-1000-8000-00805f9b34fb")); // handler 0x??
            QLowEnergyCharacteristic chb = serviceData->characteristic(b);
            if (chb.value().size() == 1)
            {
                m_battery = chb.value();
                Q_EMIT sensorUpdated();
            }
        }
*/
    }
}

void DeviceHygrotempLCD::serviceDetailsDiscovered_data(QLowEnergyService::ServiceState newState)
{
    if (newState == QLowEnergyService::ServiceDiscovered)
    {
        //qDebug() << "DeviceHygrotempLCD::serviceDetailsDiscovered_data(" << m_deviceAddress << ") > ServiceDiscovered";

        if (serviceData)
        {
            // Characteristic "Temp&Humi"
            QBluetoothUuid a(QString("226caa55-6476-4566-7562-66734470666d")); // handler 0x??
            QLowEnergyCharacteristic cha = serviceData->characteristic(a);
            m_notificationDesc = cha.descriptor(QBluetoothUuid::ClientCharacteristicConfiguration);
            serviceData->writeDescriptor(m_notificationDesc, QByteArray::fromHex("0100"));

            // Characteristic "Message"
            //QBluetoothUuid b(QString("226cbb55-6476-4566-7562-66734470666d")); // handler 0x??
        }
    }
}

/* ************************************************************************** */

void DeviceHygrotempLCD::bleWriteDone(const QLowEnergyCharacteristic &, const QByteArray &)
{
    //qDebug() << "DeviceHygrotempLCD::bleWriteDone(" << m_deviceAddress << ")";
}

void DeviceHygrotempLCD::bleReadDone(const QLowEnergyCharacteristic &c, const QByteArray &value)
{
    Q_UNUSED(c)
    Q_UNUSED(value)
/*
    const quint8 *data = reinterpret_cast<const quint8 *>(value.constData());

    qDebug() << "DeviceHygrotempLCD::bleReadDone(" << m_deviceAddress << ") on" << c.name() << " / uuid" << c.uuid() << value.size();
    qDebug() << "WE HAVE DATA: 0x" \
             << hex << data[0]  << hex << data[1]  << hex << data[2] << hex << data[3] \
             << hex << data[4]  << hex << data[5]  << hex << data[6] << hex << data[7] \
             << hex << data[8]  << hex << data[9]  << hex << data[10] << hex << data[11] \
             << hex << data[12] << hex << data[13] << hex << data[14] << hex << data[15];
*/
}

void DeviceHygrotempLCD::bleReadNotify(const QLowEnergyCharacteristic &c, const QByteArray &value)
{
    const quint8 *data = reinterpret_cast<const quint8 *>(value.constData());
/*
    qDebug() << "DeviceHygrotempLCD::bleReadNotify(" << m_deviceAddress << ") on" << c.name() << " / uuid" << c.uuid() << value.size();
    qDebug() << "WE HAVE DATA: 0x" \
             << hex << data[0]  << hex << data[1]  << hex << data[2] << hex << data[3] \
             << hex << data[4]  << hex << data[5]  << hex << data[6] << hex << data[7] \
             << hex << data[8]  << hex << data[9]  << hex << data[10] << hex << data[11] \
             << hex << data[12] << hex << data[13];
*/
    if (c.uuid().toString() == "{226caa55-6476-4566-7562-66734470666d}")
    {
        // BLE temperature & humidity sensor data // handler 0x??

        if (value.size() > 0)
        {
            // Validate data format
            if (data[1] != 0x3D && data[8] != 0x3D)
                return;

            m_temperature = value.mid(2, 4).toFloat();
            m_humidity = static_cast<int>(value.mid(9, 4).toFloat());

            m_lastUpdate = QDateTime::currentDateTime();

            if (m_dbInternal || m_dbExternal)
            {
                // SQL date format YYYY-MM-DD HH:MM:SS
                QString tsStr = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:00:00");
                QString tsFullStr = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");

                QSqlQuery addData;
                addData.prepare("REPLACE INTO plantData (deviceAddr, ts, ts_full, temperature, humidity)"
                                " VALUES (:deviceAddr, :ts, :ts_full, :temp, :humi)");
                addData.bindValue(":deviceAddr", getAddress());
                addData.bindValue(":ts", tsStr);
                addData.bindValue(":ts_full", tsFullStr);
                addData.bindValue(":temp", m_temperature);
                addData.bindValue(":humi", m_humidity);
                if (addData.exec() == false)
                    qWarning() << "> addData.exec() ERROR" << addData.lastError().type() << ":" << addData.lastError().text();

                QSqlQuery updateDevice;
                updateDevice.prepare("UPDATE devices SET deviceFirmware = :firmware, deviceBattery = :battery WHERE deviceAddr = :deviceAddr");
                updateDevice.bindValue(":firmware", m_firmware);
                updateDevice.bindValue(":battery", m_battery);
                updateDevice.bindValue(":deviceAddr", getAddress());
                if (updateDevice.exec() == false)
                    qWarning() << "> updateDevice.exec() ERROR" << updateDevice.lastError().type() << ":" << updateDevice.lastError().text();
            }

            refreshDataFinished(true);
            controller->disconnectFromDevice();

#ifndef QT_NO_DEBUG
            qDebug() << "* DeviceHygrotempLCD update:" << getAddress();
            qDebug() << "- m_firmware:" << m_firmware;
            qDebug() << "- m_battery:" << m_battery;
            qDebug() << "- m_temperature:" << m_temperature;
            qDebug() << "- m_humidity:" << m_humidity;
#endif
        }
    }
}

void DeviceHygrotempLCD::confirmedDescriptorWrite(const QLowEnergyDescriptor &d, const QByteArray &value)
{
    //qDebug() << "DeviceHygrotempLCD::confirmedDescriptorWrite!";

    if (d.isValid() && d == m_notificationDesc && value == QByteArray::fromHex("0000"))
    {
        qDebug() << "confirmedDescriptorWrite() disconnect?!";

        //disabled notifications -> assume disconnect intent
        //m_control->disconnectFromDevice();
        //delete m_service;
        //m_service = nullptr;
    }
}
