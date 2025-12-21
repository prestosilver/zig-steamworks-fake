const std = @import("std");
const log = std.log.scoped(.Steam);

pub const callback = @import("callbacks.zig");

const options = if (@hasDecl(@import("root"), "steam_options")) @import("root").steam_options else .{};

pub const fake_api = @hasDecl(options, "fake_steam") and options.fake_steam;
const enable_api = !fake_api and (@hasDecl(options, "use_steam") and options.use_steam);

pub const allocator = if (@hasDecl(options, "alloc")) options.alloc else std.heap.c_allocator;

const TEST_UGC: UGC = .{};
const TEST_UTILS: Utils = .{};
const TEST_STATS: UserStats = .{};

pub const CallbackId = enum(u32) {
    create_item = 3403,
    update_item = 3404,
};

pub const UGCQueryKind = enum(u32) {
    ranked_by_vote = 0,
    ranked_by_publication_date = 1,
    accepted_for_game_ranked_by_acceptance_date = 2,
    ranked_by_trend = 3,
};

pub const WorkshopFileType = enum(u32) {
    community = 0,
    microtransaction = 1,
    collection = 2,
    art = 3,
    video = 4,
    screenshot = 5,
    game = 6,
    game_managed_item = 15,
};

pub const Result = enum(u32) {
    ok = 1,
    fail = 2,
    no_connection = 3,
    invalid_password = 4,
    logged_in_elsewhere = 5,
    _,
};

pub const WorkshopItemVisibility = enum(u32) {
    public,
    friends_only,
    private,
    unlisted,
};

pub const AppId = enum(u32) {
    none = 0,
    this_app = if (@hasDecl(options, "app_id")) options.app_id else 480,
    _,
};

pub const User = enum(u32) {
    pub const Id = enum(u64) {
        fakeuser = 1000,
        _,
    };

    fakeuser = 1000,
    _,

    extern fn SteamAPI_ISteamUser_GetSteamID(User) Id;
    pub fn getSteamId(
        self: User,
    ) Id {
        if (enable_api) {
            return SteamAPI_ISteamUser_GetSteamID(self);
        } else {
            log.debug("Get Steam Id From User", .{});
            return .fakeuser;
        }
    }
};

fn updateFakeUGC() !void {
    const file = try std.fs.openFileAbsolute("/home/john/doc/rep/github.com/sandeee/fake_steam/ugc.csv", .{ .mode = .write_only });
    defer file.close();

    var writer = file.writer(&.{});

    for (steam_items.items) |item| {
        try writer.interface.print("{s},{s},{s}\n", .{ item.title, item.desc, item.folder });
    }
}

pub const Utils = extern struct {
    extern fn SteamAPI_ISteamUtils_IsAPICallCompleted(*const Utils, APIHandle, *bool) bool;
    pub fn isCallComplete(
        self: *const Utils,
        handle: APIHandle,
        failed: *bool,
    ) bool {
        if (enable_api) {
            return SteamAPI_ISteamUtils_IsAPICallCompleted(self, handle, failed);
        } else {
            log.debug("Check complete {}", .{handle});
            switch (handle) {
                .query => {
                    failed.* = false;
                    return true;
                },
                .create_item => {
                    failed.* = false;
                    return true;
                },
                .update_item => {
                    failed.* = false;
                    return true;
                },
            }
        }
    }

    extern fn SteamAPI_ISteamUtils_GetAPICallResult(self: *const Utils, handle: APIHandle, data: *anyopaque, data_len: u32, callback_id: CallbackId, failed: *bool) bool;
    pub fn getCallResult(
        self: *const Utils,
        comptime T: type,
        handle: APIHandle,
        data: *T,
        failed: *bool,
    ) bool {
        if (enable_api) {
            data.* = std.mem.zeroes(T);

            return SteamAPI_ISteamUtils_GetAPICallResult(
                self,
                handle,
                data,
                @intCast(@sizeOf(T)),
                T.ID,
                failed,
            );
        } else {
            get_result: {
                switch (T.ID) {
                    .create_item => {
                        const id: PublishedFileId = @enumFromInt(steam_items.items.len);
                        const path = std.fmt.allocPrint(allocator, "/home/john/doc/rep/github.com/sandeee/fake_steam/created/{}", .{id}) catch break :get_result;

                        var root = std.fs.openDirAbsolute("/", .{}) catch break :get_result;
                        defer root.close();

                        root.makePath(path) catch break :get_result;

                        steam_items.append(.{
                            .title = allocator.dupe(u8, "") catch break :get_result,
                            .desc = allocator.dupe(u8, "") catch break :get_result,
                            .folder = path,
                        }) catch
                            break :get_result;

                        updateFakeUGC() catch break :get_result;

                        data.* = .{
                            .result = .ok,
                            .file_id = id,
                            .needs_workshop_agree = false,
                        };

                        failed.* = false;
                        return true;
                    },
                    .update_item => {
                        data.* = .{
                            .result = .ok,
                            .needs_workshop_agree = false,
                        };

                        failed.* = false;
                        return true;
                    },
                }
            }

            failed.* = true;
            return false;
        }
    }
};

pub const UserStats = extern struct {};
pub const Pipe = extern struct {};

const APIHandleKind = enum {
    query,
    create_item,
    update_item,
};

pub const APIHandle = if (fake_api) union(APIHandleKind) {
    query: struct {
        handle: UGCQueryHandle,
    },
    create_item,
    update_item,
} else enum(u64) { no_handle = 0, _ };

pub const UGCQueryHandle = if (fake_api) struct {
    kind: UGCQueryKind,
    page: u32,

    pub fn deinit(self: UGCQueryHandle, ugc: *const UGC) void {
        _ = self;
        _ = ugc;
    }

    pub fn setSearchText(self: UGCQueryHandle, ugc: *const UGC, text: [:0]const u8) !void {
        _ = self;
        _ = ugc;
        _ = text;
    }
} else enum(u64) {
    _,

    extern fn SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc: *const UGC, self: UGCQueryHandle) bool;
    pub fn deinit(self: UGCQueryHandle, ugc: *const UGC) void {
        _ = SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc, self);
    }

    extern fn SteamAPI_ISteamUGC_SetSearchText(ugc: *const UGC, handle: UGCQueryHandle, text: [*:0]const u8) bool;
    pub fn setSearchText(self: UGCQueryHandle, ugc: *const UGC, text: [:0]const u8) !void {
        if (!SteamAPI_ISteamUGC_SetSearchText(ugc, self, text.ptr))
            return error.UnknownError;
    }
};

pub const PublishedFileId = enum(u64) { _ };
pub const UGC = extern struct {
    pub const ItemDetails = if (fake_api) struct {
        file_id: PubFileId,
        result: Result,
        file_type: WorkshopFileType,
        creator: AppId,
        consumer: AppId,
        title: []const u8,
        desc: []const u8,
        owner: u64,
        created: u32,
        updated: u32,
        added: u32,
        visible: u8,
        banned: bool,
        acceptable: bool,
        tags_turnic: bool,
        tags: []const u8,
        file: UGCQueryHandle,
        preview_file: UGCQueryHandle,
        file_name: []const u8,
        file_size: i32,
        preview_file_size: i32,
        rgch_url: []const u8,
        up_votes: u32,
        down_votes: u32,
        score: f32,
        children: u32,
    } else extern struct {
        file_id: PubFileId,
        result: Result,
        file_type: WorkshopFileType,
        creator: AppId,
        consumer: AppId,
        title: [129]u8,
        desc: [8000]u8,
        owner: u64,
        created: u32,
        updated: u32,
        added: u32,
        visible: u8,
        banned: bool,
        acceptable: bool,
        tags_turnic: bool,
        tags: [1025]u8,
        file: UGCQueryHandle,
        preview_file: UGCQueryHandle,
        file_name: [260]u8,
        file_size: i32,
        preview_file_size: i32,
        rgch_url: [256]u8,
        up_votes: u32,
        down_votes: u32,
        score: f32,
        children: u32,
    };

    pub const UpdateHandle = enum(u64) {
        _,

        extern fn SteamAPI_ISteamUGC_SetItemTitle(ugc: *const UGC, handle: UpdateHandle, title: [*:0]const u8) bool;
        pub fn setTitle(
            self: UpdateHandle,
            ugc: *const UGC,
            title: []const u8,
        ) bool {
            if (enable_api) {
                const tmp_title = allocator.dupeZ(u8, title) catch return false;
                defer allocator.free(tmp_title);

                return SteamAPI_ISteamUGC_SetItemTitle(ugc, self, tmp_title);
            } else {
                log.debug("Set item title: {}", .{@intFromEnum(self)});

                steam_items.items[@intFromEnum(self)].title = (allocator.realloc(steam_items.items[@intFromEnum(self)].title, title.len) catch return false);
                @memcpy(steam_items.items[@intFromEnum(self)].title, title);

                updateFakeUGC() catch return false;

                return true;
            }
        }

        extern fn SteamAPI_ISteamUGC_SetItemVisibility(ugc: *const UGC, handle: UpdateHandle, vis: WorkshopItemVisibility) bool;
        pub fn setVisibility(
            self: UpdateHandle,
            ugc: *const UGC,
            vis: WorkshopItemVisibility,
        ) bool {
            if (enable_api) {
                return SteamAPI_ISteamUGC_SetItemVisibility(ugc, self, vis);
            } else {
                log.debug("Set item vis: {}", .{@intFromEnum(self)});

                return true;
            }
        }

        extern fn SteamAPI_ISteamUGC_SetItemDescription(ugc: *const UGC, handle: UpdateHandle, desc: [*:0]const u8) bool;
        pub fn setDescription(
            self: UpdateHandle,
            ugc: *const UGC,
            desc: []const u8,
        ) bool {
            if (enable_api) {
                const tmp_desc = allocator.dupeZ(u8, desc) catch return false;
                defer allocator.free(tmp_desc);

                return SteamAPI_ISteamUGC_SetItemDescription(ugc, self, tmp_desc);
            } else {
                log.debug("Set item desc: {}", .{@intFromEnum(self)});

                steam_items.items[@intFromEnum(self)].desc = (allocator.realloc(steam_items.items[@intFromEnum(self)].desc, desc.len) catch return false);
                @memcpy(steam_items.items[@intFromEnum(self)].desc, desc);

                updateFakeUGC() catch return false;

                return true;
            }
        }

        extern fn SteamAPI_ISteamUGC_SetItemContent(ugc: *const UGC, handle: UpdateHandle, path: [*:0]const u8) bool;
        pub fn setContent(
            self: UpdateHandle,
            ugc: *const UGC,
            path: std.fs.Dir,
        ) bool {
            if (enable_api) {
                var outBuffer = std.mem.zeroes([256]u8);

                const tmp_path = path.realpathZ(".", &outBuffer) catch return false;

                return SteamAPI_ISteamUGC_SetItemContent(ugc, self, @ptrCast(tmp_path));
            } else {
                log.debug("Set item content: {}", .{@intFromEnum(self)});

                // manual guard on sandeee, hello, and cats
                if (@intFromEnum(self) < 3)
                    return false;

                if (@intFromEnum(self) > steam_items.items.len)
                    return false;

                {
                    var rm_child = std.process.Child.init(
                        &.{ "rm", "-r", steam_items.items[@intFromEnum(self)].folder },
                        allocator,
                    );
                    _ = rm_child.spawnAndWait() catch return false;
                }

                var outBuffer = std.mem.zeroes([256]u8);
                const tmp_path = path.realpath(".", &outBuffer) catch return false;

                log.debug("create path for item {s}", .{tmp_path});

                {
                    var cp_child = std.process.Child.init(
                        &.{ "cp", "-r", tmp_path, steam_items.items[@intFromEnum(self)].folder },
                        allocator,
                    );
                    _ = cp_child.spawnAndWait() catch return false;
                }

                return true;
            }
        }

        extern fn SteamAPI_ISteamUGC_SubmitItemUpdate(ugc: *const UGC, item: UpdateHandle, note: [*:0]const u8) APIHandle;
        pub fn submit(
            self: UpdateHandle,
            ugc: *const UGC,
            note: []const u8,
        ) APIHandle {
            if (enable_api) {
                const tmp_note = allocator.dupeZ(u8, note) catch return .no_handle;
                defer allocator.free(tmp_note);

                return SteamAPI_ISteamUGC_SubmitItemUpdate(ugc, self, tmp_note);
            } else {
                log.debug("Submit Update: {}", .{@intFromEnum(self)});
                return .update_item;
            }
        }
    };

    pub const PubFileId = enum(u64) { _ };

    extern fn SteamAPI_ISteamUGC_DownloadItem(ugc: *const UGC, id: PubFileId, hp: bool) bool;
    pub fn downloadItem(
        ugc: *const UGC,
        id: PubFileId,
        hp: bool,
    ) bool {
        if (enable_api) {
            return SteamAPI_ISteamUGC_DownloadItem(ugc, id, hp);
        } else {
            log.debug("Download Item: {}", .{id});
            return true;
        }
    }

    extern fn SteamAPI_ISteamUGC_CreateItem(ugc: *const UGC, appid: AppId, kind: WorkshopFileType) APIHandle;
    pub fn createItem(
        ugc: *const UGC,
        appid: AppId,
        kind: WorkshopFileType,
    ) APIHandle {
        if (enable_api) {
            return SteamAPI_ISteamUGC_CreateItem(ugc, appid, kind);
        } else {
            log.debug("CreaTeItem: kind: {}", .{kind});
            return .create_item;
        }
    }

    extern fn SteamAPI_ISteamUGC_StartItemUpdate(ugc: *const UGC, appid: AppId, item: PubFileId) UpdateHandle;
    pub fn startUpdate(
        ugc: *const UGC,
        appid: AppId,
        item: PubFileId,
    ) UpdateHandle {
        if (enable_api) {
            return SteamAPI_ISteamUGC_StartItemUpdate(ugc, appid, item);
        } else {
            log.debug("Start Update: {}", .{@intFromEnum(item)});

            const tmp: u64 = @intFromEnum(item);
            return @enumFromInt(tmp);
        }
    }

    const ItemState = packed struct {
        subscribed: bool = false,
        legacy: bool = false,
        installed: bool = false,
        needsUpdate: bool = false,
        downloading: bool = false,
        downloadpending: bool = false,
        padding: u26 = 0,

        pub fn empty(self: *const ItemState) bool {
            const v: *const u32 = @ptrCast(self);
            return v.* == 0;
        }
    };

    extern fn SteamAPI_ISteamUGC_GetItemState(ugc: *const UGC, id: PubFileId) ItemState;
    pub fn getItemState(
        ugc: *const UGC,
        id: PubFileId,
    ) ItemState {
        if (enable_api) {
            return SteamAPI_ISteamUGC_GetItemState(ugc, id);
        } else {
            return .{
                .installed = @intFromEnum(id) < steam_items.items.len,
            };
        }
    }

    extern fn SteamAPI_ISteamUGC_GetItemInstallInfo(ugc: *const UGC, id: PubFileId, size: *u64, folder: [*c]u8, folderSize: u32, timestamp: *u32) bool;
    pub fn getItemInstallInfo(
        ugc: *const UGC,
        id: PubFileId,
        size: *u64,
        folder: []u8,
        timestamp: *u32,
    ) bool {
        if (enable_api) {
            return SteamAPI_ISteamUGC_GetItemInstallInfo(ugc, id, size, folder.ptr, @intCast(folder.len), timestamp);
        } else {
            log.debug("itemInfo: {}", .{@intFromEnum(id)});

            if (@intFromEnum(id) < steam_items.items.len) {
                size.* = 0;
                const path = steam_items.items[@intFromEnum(id)].folder;
                @memcpy(folder[0..path.len], path);
                timestamp.* = 0;

                return true;
            }

            return false;
        }
    }

    extern fn SteamAPI_ISteamUGC_SendQueryUGCRequest(ugc: *const UGC, handle: UGCQueryHandle) APIHandle;
    pub fn sendQueryRequest(
        ugc: *const UGC,
        handle: UGCQueryHandle,
    ) APIHandle {
        if (enable_api) {
            return SteamAPI_ISteamUGC_SendQueryUGCRequest(ugc, handle);
        } else {
            log.debug("SendQuery: handle: {}", .{handle});
            return .{
                .query = .{
                    .handle = handle,
                },
            };
        }
    }

    const UserQuery = enum(u32) {
        published = 0,
        voted_on = 1,
        voted_up = 2,
        voted_down = 3,
        voted_later = 4,
        favorited = 5,
        subscribed = 6,
        used_or_played = 7,
        followed = 8,
    };

    const UGCMatchingType = enum(u32) {
        items = 0,
        items_mtx = 1,
        items_ready_to_use = 2,
        usable_in_game = 10,
        all = 0xffff_ffff,
    };

    const SortOrder = enum(u32) {
        create_desc = 0,
        create_asc = 1,
    };

    extern fn SteamAPI_ISteamUGC_CreateQueryUserUGCRequest(ugc: *const UGC, id: User.Id, list_type: UserQuery, kind: u32, sort: SortOrder, creator_id: AppId, consumer_id: AppId, page: u32) UGCQueryHandle;
    pub fn createUserQueryRequest(
        ugc: *const UGC,
        account: User.Id,
        query_kind: UserQuery,
        kind: u32,
        sort: SortOrder,
        creator_id: AppId,
        consumer_id: AppId,
        page: u32,
    ) UGCQueryHandle {
        if (enable_api) {
            return SteamAPI_ISteamUGC_CreateQueryUserUGCRequest(ugc, account, query_kind, kind, sort, creator_id, consumer_id, page);
        } else {
            log.debug("Query: querykind: {}, kind: {}, creator: {}, consumer: {}, page: {}", .{ query_kind, kind, creator_id, consumer_id, page });
            return .{
                .kind = .ranked_by_vote,
                .page = page,
            };
        }
    }

    extern fn SteamAPI_ISteamUGC_CreateQueryAllUGCRequestPage(ugc: *const UGC, queryKind: UGCQueryKind, kind: UGCMatchingType, creatorId: AppId, consumerId: AppId, page: u32) UGCQueryHandle;
    pub fn createQueryRequest(
        ugc: *const UGC,
        query_kind: UGCQueryKind,
        item_kind: UGCMatchingType,
        creator_id: AppId,
        consumer_id: AppId,
        page: u32,
    ) UGCQueryHandle {
        if (enable_api) {
            return SteamAPI_ISteamUGC_CreateQueryAllUGCRequestPage(ugc, query_kind, item_kind, creator_id, consumer_id, page);
        } else {
            log.debug("Query: querykind: {}, kind: {}, creator: {}, consumer: {}, page: {}", .{ query_kind, item_kind, creator_id, consumer_id, page });
            return .{
                .kind = query_kind,
                .page = page,
            };
        }
    }

    extern fn SteamAPI_ISteamUGC_GetQueryUGCResult(ugc: *const UGC, handle: UGCQueryHandle, index: u32, details: *ItemDetails) bool;
    pub fn getQueryResult(
        ugc: *const UGC,
        handle: UGCQueryHandle,
        index: u32,
        details: *ItemDetails,
    ) bool {
        if (enable_api) {
            return SteamAPI_ISteamUGC_GetQueryUGCResult(ugc, handle, index, details);
        } else {
            log.debug("query result", .{});
            if (handle.page != 1) return false;
            if (index >= steam_items.items.len) return false;

            details.* = .{
                .file_id = @enumFromInt(index),
                .result = .ok,
                .file_type = .community,
                .creator = .this_app,
                .consumer = .this_app,
                .title = steam_items.items[index].title,
                .desc = steam_items.items[index].desc,
                .owner = 0,
                .created = 0,
                .updated = 0,
                .added = 0,
                .visible = 0,
                .banned = false,
                .acceptable = true,
                .tags_turnic = false,
                .tags = "test,steam",
                .file = handle,
                .preview_file = undefined,
                .file_name = "test",
                .file_size = 0,
                .preview_file_size = 0,
                .rgch_url = "",
                .up_votes = 0,
                .down_votes = 0,
                .score = 0,
                .children = 0,
            };
            return true;
        }
    }

    extern fn SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc: *const UGC, handle: UGCQueryHandle) bool;
    pub fn releaseQueryResult(
        ugc: *const UGC,
        handle: UGCQueryHandle,
    ) bool {
        if (enable_api) {
            return SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc, handle);
        } else {
            log.debug("query free", .{});
            return false;
        }
    }
};

pub const FakeUGCEntry = struct {
    title: []u8,
    desc: []u8,
    folder: []u8,
};

pub var steam_items: std.array_list.Managed(FakeUGCEntry) = .init(allocator);

extern fn SteamAPI_Init() bool;
pub fn init() !void {
    if (enable_api) {
        if (!SteamAPI_Init()) {
            return error.SteamInitFail;
        }
        return;
    } else {
        const file = try std.fs.openFileAbsolute("/home/john/doc/rep/github.com/sandeee/fake_steam/ugc.csv", .{});
        defer file.close();

        var reader_buffer: [1024]u8 = undefined;
        var reader = file.reader(&reader_buffer);

        while (try reader.interface.takeDelimiter('\n')) |line| {
            var split = std.mem.splitScalar(u8, line, ',');

            const title = split.next() orelse continue;
            const desc = split.next() orelse continue;
            const folder = split.next() orelse continue;

            try steam_items.append(.{
                .title = try allocator.dupe(u8, title),
                .desc = try allocator.dupe(u8, desc),
                .folder = try allocator.dupe(u8, folder),
            });
        }

        log.debug("UGC Count {}", .{steam_items.items.len});
        log.debug("Init Steam", .{});

        return;
    }
}

extern fn SteamAPI_RestartAppIfNecessary(app_id: AppId) bool;
pub fn restartIfNeeded(
    app_id: AppId,
) bool {
    if (enable_api) {
        return SteamAPI_RestartAppIfNecessary(app_id);
    } else {
        log.debug("Restart If Needed: {}", .{app_id});
        return false;
    }
}

extern fn SteamAPI_Shutdown() void;
pub fn deinit() void {
    if (enable_api) {
        return SteamAPI_Shutdown();
    } else {
        for (steam_items.items) |item| {
            allocator.free(item.title);
            allocator.free(item.desc);
            allocator.free(item.folder);
        }
        steam_items.deinit();
    }
}

extern fn SteamAPI_SteamUGC_v017() *const UGC;
pub fn getSteamUGC() *const UGC {
    if (enable_api) {
        return SteamAPI_SteamUGC_v017();
    } else {
        return &TEST_UGC;
    }
}

extern fn SteamAPI_SteamUser_v023() User;
pub fn getUser() User {
    if (enable_api) {
        return SteamAPI_SteamUser_v023();
    } else {
        return .fakeuser;
    }
}

extern fn SteamAPI_SteamUtils_v010() *const Utils;
pub fn getSteamUtils() *const Utils {
    if (enable_api) {
        return SteamAPI_SteamUtils_v010();
    } else {
        return &TEST_UTILS;
    }
}

extern fn SteamAPI_SteamUserStats_v012() *const UserStats;
pub fn getUserStats() *const UserStats {
    if (enable_api) {
        return SteamAPI_SteamUserStats_v012();
    } else {
        return &TEST_STATS;
    }
}

extern fn SteamAPI_RunCallbacks() void;
pub fn runCallbacks() void {
    if (enable_api) {
        return SteamAPI_RunCallbacks();
    } else {
        return &TEST_STATS;
    }
}

pub const CALLBACK_COMPLETED = 703;

pub const CallbackMsg = extern struct {
    user: User,
    callback: i32,
    param: *void,
    param_size: i32,
};

var manual_setup: bool = false;

extern fn SteamAPI_GetHSteamPipe() *const Pipe;
extern fn SteamAPI_ManualDispatch_Init() void;
extern fn SteamAPI_ManualDispatch_RunFrame(*const Pipe) void;
extern fn SteamAPI_ManualDispatch_GetNextCallback(*const Pipe, *CallbackMsg) bool;
extern fn SteamAPI_ManualDispatch_FreeLastCallback(*const Pipe) void;
pub fn manualCallback(comptime calls: fn (CallbackMsg) anyerror!void) !void {
    if (enable_api) {
        if (!manual_setup) {
            SteamAPI_ManualDispatch_Init();
        }

        const steam_pipe = SteamAPI_GetHSteamPipe();
        SteamAPI_ManualDispatch_RunFrame(steam_pipe);
        var callback_msg: CallbackMsg = undefined;

        while (SteamAPI_ManualDispatch_GetNextCallback(steam_pipe, &callback_msg)) {
            try calls(callback_msg);

            SteamAPI_ManualDispatch_FreeLastCallback(steam_pipe);
        }
    }
}
