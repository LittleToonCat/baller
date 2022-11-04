use crate::{
    blocks::{push_disk_number, strip_disk_number, BlockId, BlockScanner},
    extract::{find_lfl_number, find_object_number, FAIL, NICE},
    index::{directory_for_block_id, read_index, Directory, Index},
    utils::vec::{extend_insert_some, grow_with_default},
    xor::XorStream,
};
use std::{
    collections::HashMap,
    error::Error,
    fmt::Write,
    fs::File,
    io::{BufReader, Read, Seek, SeekFrom},
    str,
};

pub fn extract2(
    mut path: String,
    write_file: &mut impl FnMut(&str, &[u8]) -> Result<(), Box<dyn Error>>,
) -> Result<(), Box<dyn Error>> {
    let mut f = File::open(&path)?;
    let index = read_index(&mut f)?;
    drop(f);

    let mut rooms = Vec::with_capacity(64);

    for disk_number in 1..=2 {
        strip_disk_number(&mut path);
        push_disk_number(&mut path, disk_number);
        let mut f = File::open(&path)?;
        decompile_disk(&index, disk_number, &mut f, &mut rooms, write_file)?;
        drop(f);
    }

    let mut project = String::with_capacity(1 << 10);
    for (room_number, room) in rooms.iter().enumerate() {
        let room = match room {
            Some(room) => room,
            None => continue,
        };
        writeln!(
            project,
            "room {} {:?} disk={}",
            room_number, room.name, room.disk_number,
        )?;
    }
    write_file("./project.txt", project.as_bytes())?;
    Ok(())
}

fn decompile_disk(
    index: &Index,
    disk_number: u8,
    s: &mut (impl Read + Seek),
    rooms: &mut Vec<Option<Room>>,
    write_file: &mut impl FnMut(&str, &[u8]) -> Result<(), Box<dyn Error>>,
) -> Result<(), Box<dyn Error>> {
    let s = XorStream::new(s, NICE);
    let mut s = BufReader::new(s);

    let len = s.seek(SeekFrom::End(0))?;
    s.rewind()?;

    let mut buf = Vec::with_capacity(64 << 10);
    let mut lflf_blocks = HashMap::with_capacity(16);
    let mut room_scu = String::with_capacity(1 << 10);

    let mut scan_root = BlockScanner::new(len);
    let lecf_len = scan_root
        .next_block_must_be(&mut s, *b"LECF")?
        .ok_or(FAIL)?;

    let mut scan_lecf = BlockScanner::new(s.stream_position()? + lecf_len);
    while let Some(lflf_len) = scan_lecf.next_block_must_be(&mut s, *b"LFLF")? {
        lflf_blocks.clear();
        room_scu.clear();

        let room_number =
            find_lfl_number(disk_number, s.stream_position()?, index).ok_or("LFL not in index")?;
        let mut room_named_by_number = String::new();
        let room_name = index
            .room_names
            .get(usize::try_from(room_number)?)
            .and_then(Option::as_deref)
            .unwrap_or_else(|| {
                room_named_by_number = format!("room{room_number}");
                &room_named_by_number
            });

        extend_insert_some(rooms, room_number.into(), Room {
            name: room_name.to_string(),
            disk_number,
        })?;

        let mut cx = Cx {
            index,
            disk_number,
            room_name,
            lflf_blocks: &mut lflf_blocks,
            buf: &mut buf,
            room_scu: &mut room_scu,
            indent: 0,
        };

        decompile_lflf(lflf_len, &mut s, write_file, &mut cx)?;

        write_file(&format!("./{room_name}/room.scu"), room_scu.as_bytes())?;
    }

    scan_lecf.finish(&mut s)?;

    scan_root.finish(&mut s)?;

    Ok(())
}

struct Cx<'a> {
    index: &'a Index,
    disk_number: u8,
    room_name: &'a str,
    lflf_blocks: &'a mut HashMap<BlockId, i32>,
    buf: &'a mut Vec<u8>,
    room_scu: &'a mut String,
    indent: i32,
}

fn decompile_lflf(
    lflf_len: u64,
    mut s: &mut BufReader<XorStream<&mut (impl Read + Seek)>>,
    write_file: &mut impl FnMut(&str, &[u8]) -> Result<(), Box<dyn Error>>,
    cx: &mut Cx,
) -> Result<(), Box<dyn Error>> {
    let mut scan_lflf = BlockScanner::new(s.stream_position()? + lflf_len);
    while let Some((id, len)) = scan_lflf.next_block(&mut s)? {
        match &id {
            b"RMDA" => decompile_rmda(len, s, write_file, cx)?,
            _ => decompile_raw(id, len.try_into()?, "", s, write_file, cx)?,
        }
    }
    scan_lflf.finish(&mut s)?;
    Ok(())
}

fn decompile_rmda(
    block_len: u64,
    disk_read: &mut BufReader<XorStream<&mut (impl Read + Seek)>>,
    write_file: &mut impl FnMut(&str, &[u8]) -> Result<(), Box<dyn Error>>,
    cx: &mut Cx,
) -> Result<(), Box<dyn Error>> {
    write_indent(cx.room_scu, cx.indent);
    cx.room_scu.push_str("raw-block \"RMDA\" {\n");
    cx.indent += 1;

    let mut scan = BlockScanner::new(disk_read.stream_position()? + block_len);
    while let Some((id, len)) = scan.next_block(disk_read)? {
        decompile_raw(id, len.try_into()?, "RMDA/", disk_read, write_file, cx)?;
    }
    scan.finish(disk_read)?;

    cx.indent -= 1;
    write_indent(cx.room_scu, cx.indent);
    cx.room_scu.push_str("}\n");
    Ok(())
}

fn decompile_raw(
    id: BlockId,
    len: usize,
    path_part: &str,
    disk_read: &mut BufReader<XorStream<&mut (impl Read + Seek)>>,
    write_file: &mut impl FnMut(&str, &[u8]) -> Result<(), Box<dyn Error>>,
    cx: &mut Cx,
) -> Result<(), Box<dyn Error>> {
    let offset = disk_read.stream_position()?;

    grow_with_default(cx.buf, len);
    let buf = &mut cx.buf[..len];
    disk_read.read_exact(buf)?;

    let room_name = cx.room_name;
    let id_str = str::from_utf8(&id)?;
    let glob_number = find_block_glob_number(cx.index, id, cx.disk_number, offset)?;
    let number = if let Some(n) = glob_number {
        n
    } else if let Some(n) = get_block_local_number(id, buf)? {
        n
    } else {
        let n = cx.lflf_blocks.entry(id).or_insert(0);
        *n += 1;
        *n
    };
    write_file(
        &format!("./{room_name}/{path_part}{id_str}/{number}.bin"),
        buf,
    )?;

    write_indent(cx.room_scu, cx.indent);
    write!(cx.room_scu, r#"raw-block "{id_str}""#)?;
    if let Some(glob_number) = glob_number {
        write!(cx.room_scu, " {glob_number}")?;
    }
    writeln!(cx.room_scu, r#" "{path_part}{id_str}/{number}.bin""#)?;
    Ok(())
}

fn find_block_glob_number(
    index: &Index,
    id: BlockId,
    disk_number: u8,
    offset: u64,
) -> Result<Option<i32>, Box<dyn Error>> {
    let directory = match directory_for_block_id(index, id) {
        Some(directory) => directory,
        None => return Ok(None),
    };
    Ok(Some(
        find_glob_number(index, directory, disk_number, offset).ok_or("missing from index")?,
    ))
}

fn find_glob_number(index: &Index, dir: &Directory, disk_number: u8, offset: u64) -> Option<i32> {
    find_object_number(index, dir, disk_number, offset - 8)
}

fn get_block_local_number(id: BlockId, data: &[u8]) -> Result<Option<i32>, Box<dyn Error>> {
    match &id {
        b"LSC2" => {
            let number_bytes = data.get(0..4).ok_or("local script too short")?;
            Ok(Some(i32::from_le_bytes(number_bytes.try_into().unwrap())))
        }
        _ => Ok(None),
    }
}

fn write_indent(out: &mut String, indent: i32) {
    for _ in 0..indent * 4 {
        out.push(' ');
    }
}

struct Room {
    name: String,
    disk_number: u8,
}
