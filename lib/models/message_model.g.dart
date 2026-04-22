// GENERATED CODE - DO NOT MODIFY BY HAND
// Run: flutter pub run build_runner build
//
// This is a hand-written stub so the project compiles without running
// build_runner. Replace with the real generated file after running:
//   flutter pub run build_runner build --delete-conflicting-outputs

part of 'message_model.dart';

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      id: fields[0] as String,
      text: fields[1] as String,
      encryptedText: fields[2] as String,
      isMine: fields[3] as bool,
      timestamp: fields[4] as DateTime,
      isDecryptionError: fields[5] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(6)
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
      ..write(obj.isDecryptionError);
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
