// GENERATED CODE - DO NOT MODIFY BY HAND
// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

part of 'message_model.dart';

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return Message(
      id: fields[0] as String,
      text: fields[1] as String,
      encryptedText: fields[2] as String,
      isMine: fields[3] as bool,
      timestamp: fields[4] as DateTime,
      // 🟢 FIX: Handle migration from older DB versions where these fields didn't exist
      isDecryptionError: fields[5] == null ? false : fields[5] as bool,
      isImage: fields[6] == null ? false : fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(7) // 🟢 FIX: Updated count to 7 to include the isImage field
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.encryptedText)
      ..writeByte(3)
      ..write(obj.isMine)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isDecryptionError)
      ..writeByte(6)
      ..write(obj.isImage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
