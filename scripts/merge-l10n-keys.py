#!/usr/bin/env python3
"""Merge the Core-layer message keys into Localizable.xcstrings with English
translations. zh-Hans values mirror the key (source language)."""
import json
from pathlib import Path

catalog_path = Path(__file__).resolve().parent.parent / "BNBUStudentApp" / "Resources" / "Localizable.xcstrings"

TRANSLATIONS = {
    "今天已提交过该任务。请先刷新打卡记录，勿重复提交。": "Already submitted today. Refresh your check-in records first and do not submit again.",
    "今日已打卡，不能再次开始运动。": "You have already checked in today and cannot start another session.",
    "今日已打卡，每天只能提交一次。": "You have already checked in today. Only one submission per day is allowed.",
    "免测申请已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。": "The exemption request was submitted successfully, but the local retry marker could not be cleared. Do not submit again; free up storage and reopen the app.",
    "免测申请最多只能添加 %lld 个证明材料。": "An exemption request can include at most %lld supporting files.",
    "免测申请正在提交，请勿重复操作。": "The exemption request is being submitted. Please do not repeat the action.",
    "免测补充材料已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。": "The supplementary material was submitted successfully, but the local retry marker could not be cleared. Do not submit again; free up storage and reopen the app.",
    "免测补充材料正在提交，请勿重复操作。": "The supplementary material is being submitted. Please do not repeat the action.",
    "全部凭证总大小不能超过 120MB。": "The total size of all proofs cannot exceed 120 MB.",
    "其他运动项目名称不能超过 32 个字符。": "The custom sport name cannot exceed 32 characters.",
    "凭证文件超过服务器限制，请删除过大文件后重新选择。": "A proof file exceeds the server limit. Remove the oversized file and choose again.",
    "原始文件已不在内存中，请删除后重新选择": "The original file is no longer in memory. Delete it and choose again.",
    "图片超过 8MB": "Image exceeds 8 MB",
    "学生年级尚未同步，暂时无法匹配评分组别。": "Your grade year has not been synced yet, so the scoring group cannot be matched.",
    "学生性别尚未同步，暂时无法匹配耐力跑项目。": "Your gender has not been synced yet, so the endurance run item cannot be matched.",
    "尚未上传的原始凭证已不可用；已保留待重试操作。请重新选择材料，或到“我的”中明确放弃。": "The original proofs pending upload are no longer available; the retry has been kept. Reselect your files, or discard it explicitly in Profile.",
    "已有进行中或待提交的运动，请先完成当前记录。": "An exercise session is already in progress or pending submission. Finish the current record first.",
    "已退出，但设备未能清理安全存储。请重启 App 后再登录。": "Signed out, but the device could not clear secure storage. Restart the app before signing in again.",
    "已退出，但设备未能清理待提交操作。请释放存储空间后重启 App。": "Signed out, but the device could not clear pending operations. Free up storage and restart the app.",
    "当前不在任务允许的打卡时间内，请刷新任务并确认开始和截止时间。": "Outside the allowed check-in window. Refresh and confirm the start and end times.",
    "当前不在每日打卡开放时段（%@），暂时不能开始运动。": "Outside the daily check-in window (%@). You cannot start exercising right now.",
    "当前学期没有在读体育课程，请先完成选课或联系体育部。": "No enrolled PE course this semester. Complete course selection or contact the PE department.",
    "当前网络不可用，请检查网络连接": "Network unavailable. Check your connection.",
    "当前账号无权执行此操作，请联系课程老师。": "This account is not allowed to perform this action. Contact your course teacher.",
    "打卡已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。": "The check-in was submitted successfully, but the local retry marker could not be cleared. Do not submit again; free up storage and reopen the app.",
    "提交内容不完整或格式不正确，请检查后重试。": "The submission is incomplete or malformed. Check it and try again.",
    "提交内容未通过校验，请确认任务状态、时间范围和凭证要求。": "The submission failed validation. Confirm the status, time range, and proof requirements.",
    "操作过于频繁，请稍后再试。": "Too many requests. Please try again later.",
    "无法安全保存待提交操作，已停止网络提交。请确认设备已解锁且存储空间充足，然后重试。": "Could not safely save the pending operation, so the network submission was stopped. Make sure the device is unlocked with enough storage, then retry.",
    "无法安全保存恢复时间，请释放存储空间后重试。": "Could not safely save the resume time. Free up storage and try again.",
    "无法安全保存暂停时间，请释放存储空间后重试。": "Could not safely save the pause time. Free up storage and try again.",
    "无法安全保存登录状态，请解锁设备并重试。": "Could not safely save the sign-in state. Unlock the device and try again.",
    "无法安全保存运动开始时间，请确认设备存储空间后重试。": "Could not safely save the exercise start time. Check device storage and try again.",
    "无法安全保存运动结束时间，请释放存储空间后重试。": "Could not safely save the exercise end time. Free up storage and try again.",
    "无法清理本地运动会话，请稍后重试。": "Could not clear the local exercise session. Please try again later.",
    "无法识别这项待重试操作；请明确放弃后重新提交。": "This pending retry could not be recognized; discard it explicitly and submit again.",
    "暂时无法连接校园体育服务": "Cannot reach the campus sports service right now.",
    "最多保存 %lld 张照片草稿。": "At most %lld photo drafts can be kept.",
    "最多只能添加 %lld 个凭证。": "At most %lld proofs can be added.",
    "最多只能添加 %lld 个视频。": "At most %lld videos can be added.",
    "最多只能添加 %lld 张图片。": "At most %lld images can be added.",
    "服务器数据格式发生变化，请稍后重试或联系技术支持。": "The server data format has changed. Try again later or contact technical support.",
    "服务器暂时不可用，当前显示最近同步数据。下拉或重新进入后可再次刷新。": "The server is temporarily unavailable; showing the last synced data. Pull to refresh or reopen to try again.",
    "服务器未能处理该请求，请检查提交内容或稍后重试。": "The server could not process this request. Check the submission or try again later.",
    "服务器错误（%lld），请稍后重试。": "Server error (%lld). Please try again later.",
    "本次运动数据不完整，无法提交。请结束运动后重试。": "This exercise data is incomplete and cannot be submitted. End the session and try again.",
    "校园体育服务暂时异常，请稍后重试。": "The campus sports service is temporarily unavailable. Please try again later.",
    "照片草稿无法安全保存，请检查设备存储空间。": "The photo draft could not be saved safely. Check device storage.",
    "登录已过期，且设备未能清理安全存储。请重启 App 后再登录。": "Your session expired and the device could not clear secure storage. Restart the app before signing in again.",
    "登录已过期，且设备未能清理待提交操作。请释放存储空间后重启 App。": "Your session expired and the device could not clear pending operations. Free up storage and restart the app.",
    "登录已过期，请重新登录": "Your session has expired. Please sign in again.",
    "登录已过期，请重新登录。": "Your session has expired. Please sign in again.",
    "登录操作已取消": "The sign-in was cancelled.",
    "网络连接已中断，请先刷新记录确认提交状态": "The connection was interrupted. Refresh your records first to confirm the submission status.",
    "网络错误：%@": "Network error: %@",
    "草稿列表无法安全更新，请检查设备存储空间。": "The draft list could not be updated safely. Check device storage.",
    "草稿列表无法安全更新，请稍后重试。": "The draft list could not be updated safely. Please try again later.",
    "补充材料已提交，但最新申请列表暂未同步。请稍后下拉刷新，不要重复提交。": "The supplementary material was submitted, but the latest list has not synced yet. Pull to refresh later and do not submit again.",
    "视频草稿无法安全保存，请检查设备存储空间。": "The video draft could not be saved safely. Check device storage.",
    "视频超过 100MB": "Video exceeds 100 MB",
    "记录已提交，但最新列表暂未同步。请稍后下拉刷新，不要重复提交。": "The record was submitted, but the latest list has not synced yet. Pull to refresh later and do not submit again.",
    "该待重试操作还缺少原始文件或目标已失效。请核对最新记录，或明确放弃后重新提交。": "This pending retry is missing its original files or its target no longer exists. Check the latest records, or discard it explicitly and submit again.",
    "该操作已在服务器成功提交，但本地待重试标记未能清理。请勿重复提交；释放存储空间后重新打开 App。": "The operation was submitted successfully, but the local retry marker could not be cleared. Do not submit again; free up storage and reopen the app.",
    "请先开始运动，再拍摄打卡凭证。": "Start exercising before capturing check-in proof.",
    "请填写其他运动项目名称。": "Enter the custom sport name.",
    "请填写运动说明。": "Enter the exercise description.",
    "请求的数据或服务暂不可用，请刷新后重试。": "The requested data or service is unavailable. Refresh and try again.",
    "请求超时，请检查网络后重试。": "The request timed out. Check your network and try again.",
    "请连接校园体育服务器后使用成绩换算。": "Connect to the campus sports server to use grade conversion.",
    "请选择运动项目。": "Select a sport.",
    "运动已达到 2 小时，但自动结束状态未能安全保存。请保持 App 打开并重试。": "The session reached 2 hours, but the auto-end state could not be saved safely. Keep the app open and try again.",
    "运动说明不能超过 %lld 个字符。": "The exercise description cannot exceed %lld characters.",
    "连接服务器超时，请稍后重试": "The connection to the server timed out. Please try again later.",
}

catalog = json.loads(catalog_path.read_text())
strings = catalog["strings"]
added, skipped = 0, 0
for key, en in TRANSLATIONS.items():
    if key in strings:
        skipped += 1
        continue
    strings[key] = {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": key}},
        }
    }
    added += 1

catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
print(f"added {added}, skipped(existing) {skipped}, total {len(strings)}")
