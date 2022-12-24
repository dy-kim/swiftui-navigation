import Combine
import Dependencies
import IdentifiedCollections
import SwiftUI
import SwiftUINavigation

@MainActor
final class StandupsListModel: ObservableObject {
  @Published var destination: Destination? {
    didSet { self.bind() }
  }
  @Published var standups: IdentifiedArrayOf<Standup>

  private var destinationCancellable: AnyCancellable?
  private var cancellables: Set<AnyCancellable> = []

  @Dependency(\.dataManager) var dataManager
  @Dependency(\.mainQueue) var mainQueue
  @Dependency(\.uuid) var uuid

  enum Destination {
    case add(EditStandupModel)
    case detail(StandupDetailModel)
  }

  init(
    destination: Destination? = nil
  ) {
    self.destination = destination
    self.standups = []

    do {
      self.standups = try JSONDecoder().decode(
        IdentifiedArray.self,
        from: self.dataManager.load(.standups)
      )
    } catch {
      // TODO: alert
    }

    self.$standups
      .dropFirst()
      .debounce(for: .seconds(1), scheduler: self.mainQueue)
      .sink { [weak self] standups in
        guard let self else { return }

        do {
          try self.dataManager.save(
            JSONEncoder().encode(standups),
            .standups
          )
        } catch {
          // TODO: alert
        }
      }
      .store(in: &self.cancellables)

    self.bind()
  }

  func addStandupButtonTapped() {
    self.destination = .add(
      DependencyValues.withValues(from: self) {
        EditStandupModel(standup: Standup(id: Standup.ID(self.uuid())))
      }
    )
  }

  func dismissAddStandupButtonTapped() {
    self.destination = nil
  }

  func confirmAddStandupButtonTapped() {
    defer { self.destination = nil }

    guard case let .add(editStandupModel) = self.destination
    else { return }
    var standup = editStandupModel.standup

    standup.attendees.removeAll { attendee in
      attendee.name.allSatisfy(\.isWhitespace)
    }
    if standup.attendees.isEmpty {
      standup.attendees.append(Attendee(id: Attendee.ID(self.uuid())))
    }
    self.standups.append(standup)
  }

  func standupTapped(standup: Standup) {
    self.destination = .detail(
      DependencyValues.withValues(from: self) {
        StandupDetailModel(standup: standup)
      }
    )
  }

  private func bind() {
    switch self.destination {
    case let .detail(standupDetailModel):
      standupDetailModel.onConfirmDeletion = { [weak self, id = standupDetailModel.standup.id] in
        return withAnimation {
          self?.standups.remove(id: id)
          self?.destination = nil
          return true
        }
      }

      self.destinationCancellable = standupDetailModel.$standup
        .sink { [weak self] standup in
          self?.standups[id: standup.id] = standup
        }

    case .add, .none:
      break
    }
  }
}

struct StandupsList: View {
  @ObservedObject var model: StandupsListModel

  var body: some View {
    NavigationStack {
      List {
        ForEach(self.model.standups) { standup in
          Button {
            self.model.standupTapped(standup: standup)
          } label: {
            CardView(standup: standup)
          }
          .listRowBackground(standup.theme.mainColor)
        }
      }
      .toolbar {
        Button {
          self.model.addStandupButtonTapped()
        } label: {
          Image(systemName: "plus")
        }
      }
      .navigationTitle("Daily Standups")
      .sheet(
        unwrapping: self.$model.destination,
        case: /StandupsListModel.Destination.add
      ) { $model in
        NavigationStack {
          EditStandupView(model: model)
            .navigationTitle("New standup")
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Dismiss") {
                  self.model.dismissAddStandupButtonTapped()
                }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                  self.model.confirmAddStandupButtonTapped()
                }
              }
            }
        }
      }
      .navigationDestination(
        unwrapping: self.$model.destination,
        case: /StandupsListModel.Destination.detail
      ) { $detailModel in
        StandupDetailView(model: detailModel)
      }
    }
  }
}

struct CardView: View {
  let standup: Standup

  var body: some View {
    VStack(alignment: .leading) {
      Text(self.standup.title)
        .font(.headline)
      Spacer()
      HStack {
        Label("\(self.standup.attendees.count)", systemImage: "person.3")
        Spacer()
        Label(self.standup.duration.formatted(.units()), systemImage: "clock")
          .labelStyle(.trailingIcon)
      }
      .font(.caption)
    }
    .padding()
    .foregroundColor(self.standup.theme.accentColor)
  }
}

struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.title
      configuration.icon
    }
  }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
  static var trailingIcon: Self { Self() }
}

extension URL {
  fileprivate static let standups = Self.documentsDirectory
    .appending(component: "standups.json")
}

struct StandupsList_Previews: PreviewProvider {
  static var previews: some View {
    StandupsList(
      model: DependencyValues.withValues {
        $0.dataManager = .mock(
          initialData: try! JSONEncoder().encode([
            Standup.mock,
            .engineeringMock,
            .designMock
          ])
        )
      } operation: {
        StandupsListModel()
      }
    )
  }
}