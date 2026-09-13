// cardservice form page — placeholder
// W1 块 3 之后实装: TodayReviewCard 等卡片 UI

@Entry
@Component
struct FormPage {
  @LocalStorageProp('todayReviewCount') todayReviewCount: string = '0'
  @LocalStorageProp('streakDays') streakDays: string = '0'
  @LocalStorageProp('newUnitCount') newUnitCount: string = '0'
  @LocalStorageProp('masteredPercent') masteredPercent: string = '0'

  build() {
    Column() {
      Text('今日待复习 ' + this.todayReviewCount)
        .fontSize(16)
        .fontColor('#333333')
      Text('今日新增 ' + this.newUnitCount + ' · 掌握 ' + this.masteredPercent + '%')
        .fontSize(12)
        .fontColor('#666666')
      Text('连续复习 ' + this.streakDays + ' 天')
        .fontSize(12)
        .fontColor('#666666')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
